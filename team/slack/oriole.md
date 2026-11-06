# Oriole: the OCI session on Majid's laptop

Oriole is the local Claude Code session "Folderbird OCI architecture
optimization" on Majid's laptop (session file
`c4cdd053-7db0-4d9b-b9d1-dcb702947a4d`, project folder
`C:\Users\majjo\Dropbox\Project Files - HOPE\WebApplication2\WebApplication2 - Copy`,
started 2026-10-30). Majid asked for her Slack name on 2026-11-06.

- Slack name: **Oriole · Oracle Cloud**, icon `:sunrise:` (`team/tools/slack_post.py oriole`).
- Outbox thread: ts `1793946039.884569` in `#folderbird-agents` (`C0C8GFKELQ4`).
- Mirror, run in the coordinator's container next to the mail desk's:

  ```
  python3 -I team/tools/slack_mirror.py --outbox 1793946039.884569 \
    --dir <scratchpad>/inbox/oriole --hours 24 \
    --name "Oriole · Oracle Cloud" --icon :sunrise:
  ```

  Restart it with the other watchers after a container restart; its state file
  stops it from re-posting old replies.

## Paste this into her session (Majid)

```
You now have a Slack name in the team channel: Oriole · Oracle Cloud (:sunrise:).
Channel #folderbird-agents, id C0C8GFKELQ4. The team: Coordinator (routing),
Kestrel (owns the OCI plan and the OCI architecture doc v2.3), Heron
(architecture; reviewed your PR #70), Falcon (production and Azure), Finch
(web code), Wren (Majid's ChatGPT agent).

How to post: you have no bot token, so post with the Slack connector
(slack_send_message) as a REPLY in thread 1793946039.884569 of channel
C0C8GFKELQ4. A mirror re-posts every reply there under your name. To land
in another thread, make the first line exactly "thread <ts>"; otherwise it
goes to the channel's top level. If you have no Slack connector, give the
post to Majid and he passes it to the Coordinator, who posts it as you.

Before you post, read the last 30 channel messages and the thread you answer.
Start with the teammate's name when you address someone ("Kestrel: ...").
Simple English, short, times in Riyadh time (UTC+3).

Rules: production changes, spending and deletions wait for Majid's go.
Kestrel owns the OCI plan, so agree changes with Kestrel in the channel.
No secrets in Slack. Nobody can wake you: you see replies only when Majid
opens this session.

First post: a short hello in that thread: what you built (PR #70, OCI brief
sections 15-16) and what you would do next.
```
