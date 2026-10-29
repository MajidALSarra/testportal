#!/usr/bin/env python3
"""Post to #folderbird-agents as one agent, with that agent's own name and icon.

Usage:
  python3 team/tools/slack_post.py <agent-key> <message-file|-> [--thread <ts>]

The Folderbird Agents bot token is stored as a network secret in the cloud
environment, so the network gateway adds it to requests to slack.com and no
token is needed here. If SLACK_BOT_TOKEN is set, it is sent instead.
Prints the new message's ts on success.
"""
import json, os, ssl, sys, urllib.request

CHANNEL = "C0C8GFKELQ4"
AGENTS = {
    "coordinator": ("Coordinator", ":compass:"),
    "falcon": ("Falcon · Ops", ":eagle:"),
    "swift": ("Swift · Windows app", ":bird:"),
    "heron": ("Heron · Architecture", ":flamingo:"),
    "kestrel": ("Kestrel · Cloud", ":owl:"),
    "robin": ("Robin · iOS", ":parrot:"),
    "peacock": ("Peacock · Marketing", ":peacock:"),
    "magpie": ("Magpie · Demo PC", ":desktop_computer:"),
    "sparrow": ("Sparrow · Release", ":rocket:"),
    "pigeon": ("Pigeon · Relay", ":dove_of_peace:"),
    "finch": ("Finch · Web", ":hatched_chick:"),
}

def main(argv):
    if len(argv) < 3 or argv[1] not in AGENTS:
        sys.exit("usage: slack_post.py <" + "|".join(AGENTS) + "> <message-file|-> [--thread <ts>]")
    token = os.environ.get("SLACK_BOT_TOKEN", "")
    text = sys.stdin.read() if argv[2] == "-" else open(argv[2], encoding="utf-8").read()
    name, icon = AGENTS[argv[1]]
    body = {"channel": CHANNEL, "text": text.strip(), "username": name, "icon_emoji": icon,
            "unfurl_links": False}
    if "--thread" in argv:
        body["thread_ts"] = argv[argv.index("--thread") + 1]
    cafile = os.environ.get("SSL_CERT_FILE") or ("/root/.ccr/ca-bundle.crt" if os.path.exists("/root/.ccr/ca-bundle.crt") else None)
    ctx = ssl.create_default_context(cafile=cafile) if cafile else ssl.create_default_context()
    headers = {"Content-Type": "application/json; charset=utf-8"}
    if token:
        headers["Authorization"] = "Bearer " + token
    req = urllib.request.Request("https://slack.com/api/chat.postMessage", data=json.dumps(body).encode(),
                                 headers=headers)
    with urllib.request.urlopen(req, context=ctx, timeout=30) as r:
        out = json.load(r)
    if not out.get("ok"):
        sys.exit("slack error: " + str(out.get("error")))
    print(out["ts"])

if __name__ == "__main__":
    main(sys.argv)
