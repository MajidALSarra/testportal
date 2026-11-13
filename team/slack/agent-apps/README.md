# Per-agent Slack apps (so Majid can type @Falcon)

Researched 2026-11-13 for Majid's ask "make the team actual agents, I need to call them with @".

- Slack only lets you @ a member. A `username` override on `chat.postMessage` creates no member,
  so each mentionable agent needs its own Slack app (one app = one bot user). Wren and Kite are
  already bot users built this way.
- Each app here is inert: one bot user, `chat:write` only, no events, no server. Nobody copies its
  token. Agents keep posting through Folderbird Agents with their name override. The Coordinator's
  watcher reads the channel history and routes `<@U…>` mentions to the agent's session.
- Majid creates each app from a prefilled link
  (`https://api.slack.com/apps?new_app=1&manifest_yaml=<url-encoded yaml, comments stripped>`),
  installs it, and runs `/invite @Name` in #folderbird-agents. If the link does not prefill,
  use Create New App → From a manifest and paste the YAML.
- Slack free plan: at most 10 apps, custom ones included. Folderbird Agents, Wren, Kite and the
  Claude connector already use 4. User groups are paid-only and cannot contain bots.
- Claude Tag (Team/Enterprise) gives one @Claude per workspace with fresh per-thread sessions; it
  does not provide named agents or attach our existing sessions.
- Posting as the agent's own bot would need that app's token, i.e. one cloud environment per
  agent (the proxy injects one slack.com credential per environment). Later, per agent, opt-in.

Plan: test with `falcon.yaml` first. If `@Falcon ping` reaches Falcon, make the rest, then change
`team/tools/slack_inbox.py` to route by mention id (plus the old `Name:` prefix), queue Wren and
agent posts that mention someone, and cap agent-to-agent delivery at 6 per recipient per hour.
