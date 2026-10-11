#!/usr/bin/env python3
"""Instant receipts for Majid's messages in #folderbird-agents.

Three commands:

  python3 team/tools/slack_inbox.py react --dir <state dir> [--hours 12]
      Long-running. Every 2 s it reads the channel and every thread with new
      replies. Each new message Majid typed (top level or in a thread) gets
      :eyes: from the Folderbird Agents bot at once and is appended to
      <dir>/queue.jsonl. Writes <dir>/heartbeat every loop and one line per
      receipt to <dir>/receipts.log (ts, thread, milliseconds; no text).

  python3 team/tools/slack_inbox.py wait --dir <state dir> [--minutes 100]
      Exits as soon as queue.jsonl holds a message not yet in handled.txt,
      printing those messages as JSON lines; or prints REACTOR_DOWN when the
      heartbeat is older than 30 s; or TIMEOUT after --minutes.

  python3 team/tools/slack_inbox.py done --dir <state dir> <ts> [<ts> ...]
      Marks messages handled and adds the bot's :incoming_envelope: to each.

  python3 team/tools/slack_inbox.py scan --since <ts>
      Read-only: prints Majid's messages newer than <ts>, threads included.

The cloud gateway adds the bot token to requests to slack.com, so no token is
needed here. Majid's own messages are user U0C8GF0RF5J with no bot_id and no
app_id; posts the Claude connector makes under his name carry an app_id.
"""
import json
import os
import ssl
import sys
import time
import urllib.parse
import urllib.request

CHANNEL = "C0C8GFKELQ4"
MAJID = "U0C8GF0RF5J"
CAFILE = "/root/.ccr/ca-bundle.crt"
INTERVAL = 2.0
CTX = ssl.create_default_context(cafile=CAFILE if os.path.exists(CAFILE) else None)


def api(method, params=None, post=None):
    """Call a Slack Web API method; on HTTP 429 wait Retry-After and retry."""
    for _ in range(5):
        if post is None:
            url = f"https://slack.com/api/{method}?" + urllib.parse.urlencode(params or {})
            req = urllib.request.Request(url)
        else:
            req = urllib.request.Request(
                f"https://slack.com/api/{method}",
                data=json.dumps(post).encode(),
                headers={"Content-Type": "application/json; charset=utf-8"},
            )
        try:
            with urllib.request.urlopen(req, context=CTX, timeout=15) as r:
                return json.load(r)
        except urllib.error.HTTPError as e:
            if e.code != 429:
                raise
            time.sleep(int(e.headers.get("Retry-After", "5")))
    raise RuntimeError(f"{method}: still rate limited")


def is_majid(m):
    return (
        m.get("user") == MAJID
        and not m.get("bot_id")
        and not m.get("app_id")
        and m.get("subtype") in (None, "thread_broadcast", "file_share")
    )


def bot_reacted(m, name, bot_user):
    return any(r.get("name") == name and bot_user in r.get("users", []) for r in m.get("reactions", []))


def history(limit=100):
    r = api("conversations.history", {"channel": CHANNEL, "limit": limit})
    if not r.get("ok"):
        raise RuntimeError(f"history: {r.get('error')}")
    return r["messages"]


def replies(parent_ts, oldest):
    r = api("conversations.replies", {"channel": CHANNEL, "ts": parent_ts, "oldest": oldest, "limit": 200})
    if not r.get("ok"):
        raise RuntimeError(f"replies: {r.get('error')}")
    return [m for m in r["messages"] if m["ts"] != parent_ts]


def entry(m, parent=None):
    e = {"ts": m["ts"], "thread_ts": m.get("thread_ts"), "text": m.get("text", "")}
    if parent is not None:
        e["thread_starter"] = parent.get("username") or parent.get("user")
        e["thread_text"] = (parent.get("text") or "")[:300]
    return e


def new_majid_messages(watermark, last_latest, seen):
    """Yield (message, parent) for Majid messages newer than watermark not in seen."""
    for m in history():
        if is_majid(m) and float(m["ts"]) > watermark and m["ts"] not in seen:
            yield m, None
        lr = m.get("latest_reply")
        if lr and float(lr) > watermark and last_latest.get(m["ts"]) != lr:
            since = last_latest.get(m["ts"]) or f"{watermark:.6f}"
            for r in replies(m["ts"], since):
                if is_majid(r) and float(r["ts"]) > watermark and r["ts"] not in seen:
                    yield r, m
            last_latest[m["ts"]] = lr


def react(d, hours):
    os.makedirs(d, exist_ok=True)
    bot_user = api("auth.test", post={})["user_id"]
    state_file = os.path.join(d, "state.json")
    try:
        state = json.load(open(state_file))
    except (OSError, ValueError):
        # First start: no back-fill, only messages from two minutes ago on.
        state = {"watermark": time.time() - 120, "last_latest": {}, "seen": []}
    seen = set(state["seen"])
    stop = time.time() + hours * 3600
    log = open(os.path.join(d, "receipts.log"), "a", buffering=1)
    log.write(f"{time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())} start bot={bot_user} pid={os.getpid()}\n")
    while time.time() < stop:
        t0 = time.time()
        try:
            for m, parent in new_majid_messages(state["watermark"], state["last_latest"], seen):
                status = "already"
                if not bot_reacted(m, "eyes", bot_user):
                    r = api("reactions.add", post={"channel": CHANNEL, "timestamp": m["ts"], "name": "eyes"})
                    status = "ok" if r.get("ok") or r.get("error") == "already_reacted" else r.get("error")
                ms = int((time.time() - float(m["ts"])) * 1000)
                log.write(f"{m['ts']} thread={m.get('thread_ts') or '-'} eyes={status} ms={ms}\n")
                with open(os.path.join(d, "queue.jsonl"), "a") as q:
                    q.write(json.dumps(entry(m, parent)) + "\n")
                seen.add(m["ts"])
            state["seen"] = sorted(seen)[-500:]
            with open(state_file + ".tmp", "w") as f:
                json.dump(state, f)
            os.replace(state_file + ".tmp", state_file)
        except Exception as e:  # keep running through network and API errors
            log.write(f"{time.strftime('%H:%M:%SZ', time.gmtime())} error {type(e).__name__}: {e}\n")
            time.sleep(5)
        with open(os.path.join(d, "heartbeat"), "w") as f:
            f.write(f"{time.time():.3f}\n")
        time.sleep(max(0.0, INTERVAL - (time.time() - t0)))
    log.write("stop: lifetime reached\n")


def handled(d):
    try:
        return set(open(os.path.join(d, "handled.txt")).read().split())
    except OSError:
        return set()


def wait(d, minutes):
    stop = time.time() + minutes * 60
    while time.time() < stop:
        done = handled(d)
        try:
            pending = [json.loads(l) for l in open(os.path.join(d, "queue.jsonl")) if l.strip()]
        except OSError:
            pending = []
        pending = [p for p in pending if p["ts"] not in done]
        if pending:
            time.sleep(3)  # let a burst of messages arrive together
            done = handled(d)
            pending = [json.loads(l) for l in open(os.path.join(d, "queue.jsonl")) if l.strip()]
            for p in pending:
                if p["ts"] not in done:
                    print(json.dumps(p, ensure_ascii=False))
            return
        try:
            beat = float(open(os.path.join(d, "heartbeat")).read())
        except (OSError, ValueError):
            beat = 0
        if time.time() - beat > 30:
            print("REACTOR_DOWN")
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
    for m, parent in new_majid_messages(float(since), {}, set()):
        print(json.dumps(entry(m, parent), ensure_ascii=False))


if __name__ == "__main__":
    args = sys.argv[1:]
    opt = lambda name, default: args[args.index(name) + 1] if name in args else default
    cmd = args[0] if args else ""
    if cmd == "react":
        react(opt("--dir", "."), float(opt("--hours", "12")))
    elif cmd == "wait":
        wait(opt("--dir", "."), float(opt("--minutes", "100")))
    elif cmd == "done":
        done(opt("--dir", "."), [a for a in args[1:] if a[0].isdigit() and "." in a])
    elif cmd == "scan":
        scan(opt("--since", f"{time.time() - 3600:.6f}"))
    else:
        sys.exit(__doc__)
