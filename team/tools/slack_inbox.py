#!/usr/bin/env python3
"""Instant receipts for Majid's messages in #folderbird-agents.

  python3 team/tools/slack_inbox.py react --dir <state dir> [--hours 12] [--also U1,U2]
      Long-running, one per --dir (react.lock). Every 1.75 s it reads the
      newest top-level messages and every thread whose latest reply changed.
      Every 30 s, and after a start or an error, it also pages back 7 days so
      replies in old threads and messages missed during downtime are found.
      Each new message Majid typed gets the bot's :eyes: (failed receipts are
      retried) and is appended to <dir>/queue.jsonl. Writes <dir>/heartbeat
      every loop, <dir>/last_ok after each good pass, <dir>/last_error after a
      failed one, and one line per receipt to <dir>/receipts.log (ts, thread,
      milliseconds; never message text).

  python3 team/tools/slack_inbox.py wait --dir <state dir> [--minutes 100]
      Exits as soon as queue.jsonl holds a message not yet in handled.txt and
      prints those messages as JSON lines. Prints REACTOR_DOWN when the reactor
      is gone, REACTOR_FAILING <error> when it runs but its passes fail, or
      TIMEOUT after --minutes.

  python3 team/tools/slack_inbox.py done --dir <state dir> <ts> [<ts> ...]
      Marks messages handled and adds the bot's :incoming_envelope: to each.

  python3 team/tools/slack_inbox.py scan --since <ts>
      Read-only: prints Majid's messages newer than <ts>, threads included.

The cloud gateway adds the bot token to requests to slack.com, so no token is
needed here. Majid's own messages are user U0C8GF0RF5J with no bot_id and no
app_id; posts the Claude connector makes under his name carry an app_id.
"""
import fcntl
import json
import os
import ssl
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

CHANNEL = "C0C8GFKELQ4"
MAJID = "U0C8GF0RF5J"
WATCHED = {MAJID}  # plus any --also users (teammates who are people or other AIs, e.g. Wren)
CAFILE = "/root/.ccr/ca-bundle.crt"
INTERVAL = 1.75        # fast pass: about 34 history calls a minute, Tier 3 allows 50
FAST_LIMIT = 30        # newest top-level messages read on each fast pass
SWEEP_EVERY = 30.0     # seconds between deep sweeps
SWEEP_DAYS = 7         # how far back a deep sweep pages
TRANSIENT = {"internal_error", "fatal_error", "service_unavailable", "request_timeout",
             "ratelimited", "not_authed", "invalid_auth"}
CTX = ssl.create_default_context(cafile=CAFILE if os.path.exists(CAFILE) else None)
_beat_path = None


def write_atomic(path, text):
    tmp = f"{path}.{os.getpid()}.tmp"
    with open(tmp, "w") as f:
        f.write(text)
    os.replace(tmp, path)


def beat():
    if _beat_path:
        write_atomic(_beat_path, f"{time.time():.3f}\n")


def api(method, params=None, post=None):
    """Call a Slack Web API method; on HTTP 429 wait Retry-After (beating) and retry."""
    for _ in range(4):
        beat()
        if post is None:
            req = urllib.request.Request(f"https://slack.com/api/{method}?" + urllib.parse.urlencode(params or {}))
        else:
            req = urllib.request.Request(
                f"https://slack.com/api/{method}",
                data=json.dumps(post).encode(),
                headers={"Content-Type": "application/json; charset=utf-8"},
            )
        try:
            with urllib.request.urlopen(req, context=CTX, timeout=5) as r:
                return json.load(r)
        except urllib.error.HTTPError as e:
            if e.code != 429:
                raise
            wait_s = min(int(e.headers.get("Retry-After", "3")), 30)
            for _ in range(wait_s):
                time.sleep(1)
                beat()
    raise RuntimeError(f"{method}: still rate limited")


def is_majid(m):
    """A message typed by Majid, or posted by a watched teammate such as Wren.
    Majid's own messages have no bot_id and no app_id; posts the Claude
    connector makes under his name carry an app_id and are skipped. A watched
    teammate like Wren posts through its own app, so its bot_id is allowed."""
    if m.get("subtype") not in (None, "thread_broadcast", "file_share"):
        return False
    if m.get("user") == MAJID:
        return not m.get("bot_id") and not m.get("app_id")
    return m.get("user") in WATCHED


def bot_reacted(m, name, bot_user):
    return any(r.get("name") == name and bot_user in r.get("users", []) for r in m.get("reactions", []))


def history(limit, oldest=None, pages=1):
    """Top-level messages, newest first; follows the cursor for up to `pages` pages."""
    params = {"channel": CHANNEL, "limit": limit}
    if oldest:
        params["oldest"] = f"{oldest:.6f}"
    out = []
    for _ in range(pages):
        r = api("conversations.history", params)
        if not r.get("ok"):
            raise RuntimeError(f"history: {r.get('error')}")
        out += r["messages"]
        cursor = (r.get("response_metadata") or {}).get("next_cursor")
        if not r.get("has_more") or not cursor:
            break
        params["cursor"] = cursor
    return out


def replies(parent_ts, oldest):
    """Every reply after `oldest` (exclusive), following the cursor; parent excluded."""
    params = {"channel": CHANNEL, "ts": parent_ts, "oldest": oldest, "limit": 200}
    out = []
    for _ in range(20):
        r = api("conversations.replies", params)
        if not r.get("ok"):
            raise RuntimeError(f"replies: {r.get('error')}")
        out += [m for m in r["messages"] if m["ts"] != parent_ts]
        cursor = (r.get("response_metadata") or {}).get("next_cursor")
        if not r.get("has_more") or not cursor:
            break
        params["cursor"] = cursor
    return out


def entry(m, parent=None):
    e = {"ts": m["ts"], "thread_ts": m.get("thread_ts"), "user": m.get("user"), "text": m.get("text", "")}
    if parent is not None:
        e["thread_starter"] = parent.get("username") or parent.get("user")
        e["thread_text"] = (parent.get("text") or "")[:300]
    return e


def new_majid_messages(messages, watermark, last_latest, seen):
    """From top-level `messages`, return [(message, parent)] for new Majid messages,
    top level and in threads whose latest_reply changed. last_latest is updated
    only for threads whose replies were fully read."""
    found = []
    for m in messages:
        if is_majid(m) and float(m["ts"]) > watermark and m["ts"] not in seen:
            found.append((m, None))
        lr = m.get("latest_reply")
        if lr and float(lr) > watermark and last_latest.get(m["ts"]) != lr:
            since = last_latest.get(m["ts"]) or f"{watermark:.6f}"
            for r in replies(m["ts"], since):
                if is_majid(r) and float(r["ts"]) > watermark and r["ts"] not in seen:
                    found.append((r, m))
            last_latest[m["ts"]] = lr
    return found


def add_eyes(ts, bot_user, m=None):
    if m is not None and bot_reacted(m, "eyes", bot_user):
        return "already"
    r = api("reactions.add", post={"channel": CHANNEL, "timestamp": ts, "name": "eyes"})
    if r.get("ok") or r.get("error") == "already_reacted":
        return "ok"
    return r.get("error") or "unknown"


def react(d, hours):
    global _beat_path
    os.makedirs(d, exist_ok=True)
    lock = open(os.path.join(d, "react.lock"), "a+")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        print("another reactor holds the lock; exiting")
        return
    lock.seek(0)
    lock.truncate()
    lock.write(f"{os.getpid()}\n")
    lock.flush()
    _beat_path = os.path.join(d, "heartbeat")
    log = open(os.path.join(d, "receipts.log"), "a", buffering=1)
    stamp = lambda: time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    state_file = os.path.join(d, "state.json")
    try:
        state = json.load(open(state_file))
    except (OSError, ValueError):
        # First start: no back-fill, only messages from two minutes ago on.
        state = {"watermark": time.time() - 120, "last_latest": {}, "seen": []}
    state.setdefault("pending_eyes", {})
    seen = set(state["seen"])
    bot_user = api("auth.test", post={})["user_id"]
    log.write(f"{stamp()} start bot={bot_user} pid={os.getpid()}\n")
    stop = time.time() + hours * 3600
    next_sweep = 0.0  # sweep on the first pass
    failures = 0
    while time.time() < stop:
        t0 = time.time()
        try:
            # 1. Retry receipts that failed earlier.
            for ts, tries in list(state["pending_eyes"].items()):
                status = add_eyes(ts, bot_user)
                log.write(f"{ts} eyes_retry={tries} status={status}\n")
                if status == "ok" or status not in TRANSIENT or tries >= 5:
                    del state["pending_eyes"][ts]
                else:
                    state["pending_eyes"][ts] = tries + 1
            # 2. Fast pass, or a deep sweep every SWEEP_EVERY seconds.
            if t0 >= next_sweep:
                # Not limited by the watermark: an old parent can get a new reply.
                messages = history(200, oldest=time.time() - SWEEP_DAYS * 86400, pages=20)
                next_sweep = t0 + SWEEP_EVERY
            else:
                messages = history(FAST_LIMIT)
            # 3. Receipt first, then queue.
            for m, parent in new_majid_messages(messages, state["watermark"], state["last_latest"], seen):
                status = add_eyes(m["ts"], bot_user, m)
                if status not in ("ok", "already") and status in TRANSIENT:
                    state["pending_eyes"][m["ts"]] = 1
                ms = int((time.time() - float(m["ts"])) * 1000)
                log.write(f"{m['ts']} thread={m.get('thread_ts') or '-'} eyes={status} ms={ms}\n")
                e = entry(m, parent)
                e["eyes"] = status
                with open(os.path.join(d, "queue.jsonl"), "a") as q:
                    q.write(json.dumps(e) + "\n")
                seen.add(m["ts"])
            # 4. Save state; drop threads older than the sweep horizon.
            horizon = time.time() - SWEEP_DAYS * 86400
            state["last_latest"] = {k: v for k, v in state["last_latest"].items() if float(v) > horizon}
            state["seen"] = sorted(seen, key=float)[-2000:]
            write_atomic(state_file, json.dumps(state))
            write_atomic(os.path.join(d, "last_ok"), f"{time.time():.3f}\n")
            failures = 0
        except Exception as e:  # keep running through network and API errors
            failures += 1
            msg = f"{type(e).__name__}: {e}"
            log.write(f"{stamp()} error {msg}\n")
            write_atomic(os.path.join(d, "last_error"), f"{time.time():.3f} {msg}\n")
            next_sweep = 0.0  # catch up with a deep sweep after an error
            time.sleep(min(1.0 * failures, 5.0))
        beat()
        time.sleep(max(0.0, INTERVAL - (time.time() - t0)))
    log.write(f"{stamp()} stop: lifetime reached\n")


def read_float(path):
    try:
        return float(open(path).read().split()[0])
    except (OSError, ValueError, IndexError):
        return None


def reactor_alive(d):
    """True when some process holds react.lock."""
    try:
        with open(os.path.join(d, "react.lock"), "a+") as f:
            fcntl.flock(f, fcntl.LOCK_EX | fcntl.LOCK_NB)
            fcntl.flock(f, fcntl.LOCK_UN)
            return False
    except BlockingIOError:
        return True


def pending(d):
    try:
        done_ts = set(open(os.path.join(d, "handled.txt")).read().split())
    except OSError:
        done_ts = set()
    out, ts_seen = [], set()
    try:
        lines = open(os.path.join(d, "queue.jsonl")).read().splitlines()
    except OSError:
        lines = []
    for line in lines:
        try:
            p = json.loads(line)
        except ValueError:
            continue  # a line still being written
        if p["ts"] not in done_ts and p["ts"] not in ts_seen:
            ts_seen.add(p["ts"])
            out.append(p)
    return out


def wait(d, minutes):
    started = time.time()
    stop = started + minutes * 60
    stale = 0
    while time.time() < stop:
        if pending(d):
            time.sleep(3)  # let a burst of messages arrive together
            for p in pending(d):
                print(json.dumps(p, ensure_ascii=False))
            return
        now = time.time()
        hb = read_float(os.path.join(d, "heartbeat"))
        if hb is None or now - hb > 30:
            stale += 1
            if stale >= 2 and not reactor_alive(d):
                print("REACTOR_DOWN")
                return
        else:
            stale = 0
        ok = read_float(os.path.join(d, "last_ok")) or started
        if now - max(ok, started) > 60:
            try:
                err = open(os.path.join(d, "last_error")).read().strip()
            except OSError:
                err = "no error recorded"
            print(f"REACTOR_FAILING {err}")
            return
        time.sleep(1)
    print("TIMEOUT")


def done(d, ts_list):
    with open(os.path.join(d, "handled.txt"), "a") as f:
        for ts in ts_list:
            f.write(ts + "\n")
            r = api("reactions.add", post={"channel": CHANNEL, "timestamp": ts, "name": "incoming_envelope"})
            print(ts, "ok" if r.get("ok") or r.get("error") == "already_reacted" else r.get("error"))


def scan(since):
    messages = history(200, oldest=time.time() - SWEEP_DAYS * 86400, pages=20)
    for m, parent in new_majid_messages(messages, float(since), {}, set()):
        print(json.dumps(entry(m, parent), ensure_ascii=False))


if __name__ == "__main__":
    args = sys.argv[1:]

    def opt(name, default):
        i = args.index(name) if name in args else -1
        return args[i + 1] if 0 <= i < len(args) - 1 else default

    cmd = args[0] if args else ""
    WATCHED.update(u for u in opt("--also", "").split(",") if u)
    if cmd == "react":
        react(opt("--dir", "."), float(opt("--hours", "12")))
    elif cmd == "wait":
        wait(opt("--dir", "."), float(opt("--minutes", "100")))
    elif cmd == "done":
        done(opt("--dir", "."), [a for a in args[1:] if a.replace(".", "").isdigit() and "." in a])
    elif cmd == "scan":
        scan(opt("--since", f"{time.time() - 3600:.6f}"))
    else:
        sys.exit(__doc__)
