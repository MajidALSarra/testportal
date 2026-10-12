#!/usr/bin/env python3
"""Re-post the Chrome mail desk's Slack posts under its own name.

The mail desk ("Email sending setup", a Claude in Chrome chat) can post in
Slack only through the Claude Slack connector, which posts as Majid. So it
posts as a reply in one outbox thread, and this script copies each new post
there to #folderbird-agents as "Mail Desk · Chrome", then marks the original
with :white_check_mark:.

A first line of `thread <ts>` sends the post into that thread; otherwise it
goes to the channel's top level. The connector's "Sent using Claude" footer
is dropped.

  python3 team/tools/slack_mirror.py --outbox <thread ts> --dir <state dir> [--hours 24]

The cloud gateway adds the bot token, as for slack_post.py.
"""
import fcntl
import json
import os
import re
import ssl
import sys
import time
import urllib.parse
import urllib.request

CHANNEL = "C0C8GFKELQ4"
CONNECTOR_APP = "A08SF47R6P4"  # the Claude Slack connector, posting as Majid
NAME, ICON = "Mail Desk · Chrome", ":e-mail:"
CAFILE = "/root/.ccr/ca-bundle.crt"
CTX = ssl.create_default_context(cafile=CAFILE if os.path.exists(CAFILE) else None)


def api(method, params=None, post=None):
    if post is None:
        req = urllib.request.Request(f"https://slack.com/api/{method}?" + urllib.parse.urlencode(params or {}))
    else:
        req = urllib.request.Request(f"https://slack.com/api/{method}", data=json.dumps(post).encode(),
                                     headers={"Content-Type": "application/json; charset=utf-8"})
    with urllib.request.urlopen(req, context=CTX, timeout=10) as r:
        return json.load(r)


def clean(text):
    text = re.sub(r"\s*\*?Sent using\*?\s+(<[^>]*\|)?\s*Claude>?\s*$", "", text.strip())
    m = re.match(r"\s*thread\s+(\d{10}\.\d{6})\s*\n?", text, re.I)
    if m:
        return text[m.end():].strip(), m.group(1)
    return text, None


def run(outbox, d, hours):
    os.makedirs(d, exist_ok=True)
    lock = open(os.path.join(d, "mirror.lock"), "a+")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        print("another mirror holds the lock; exiting")
        return
    state_file = os.path.join(d, "mirror.json")
    try:
        last = json.load(open(state_file))["last"]
    except (OSError, ValueError, KeyError):
        last = f"{time.time() - 60:.6f}"
    log = open(os.path.join(d, "mirror.log"), "a", buffering=1)
    log.write(f"{time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())} start outbox={outbox} pid={os.getpid()}\n")
    stop = time.time() + hours * 3600
    while time.time() < stop:
        try:
            r = api("conversations.replies", {"channel": CHANNEL, "ts": outbox, "oldest": last, "limit": 100})
            for m in r.get("messages", []):
                if m["ts"] == outbox or float(m["ts"]) <= float(last):
                    continue
                if m.get("app_id") == CONNECTOR_APP and not m.get("bot_id"):
                    body, target = clean(m.get("text", ""))
                    post = {"channel": CHANNEL, "text": body, "username": NAME, "icon_emoji": ICON}
                    if target:
                        post["thread_ts"] = target
                    res = api("chat.postMessage", post=post)
                    if res.get("ok"):
                        api("reactions.add", post={"channel": CHANNEL, "timestamp": m["ts"], "name": "white_check_mark"})
                    log.write(f"{m['ts']} -> {target or 'top'} ok={res.get('ok')} {res.get('error') or ''}\n")
                last = m["ts"]
            with open(state_file, "w") as f:
                json.dump({"last": last}, f)
        except Exception as e:
            log.write(f"{time.strftime('%H:%M:%SZ', time.gmtime())} error {type(e).__name__}: {e}\n")
            time.sleep(5)
        time.sleep(3)


if __name__ == "__main__":
    a = sys.argv[1:]
    opt = lambda n, dflt: a[a.index(n) + 1] if n in a and a.index(n) + 1 < len(a) else dflt
    if "--outbox" not in a:
        sys.exit(__doc__)
    run(opt("--outbox", ""), opt("--dir", "."), float(opt("--hours", "24")))
