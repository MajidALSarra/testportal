# Team room sources

- `room.html` is the source of the Folderbird Team Room page,
  https://claude.ai/artifact/MonDhz4FLkicysFNUeqTAh. To change the page, edit
  this file and publish it to that URL with the Artifact tool (pass the URL as
  `url`, after reading the live version). The page declares only the `db`
  and `user` capabilities. It saves and shows messages, and agents are woken
  through the coordinator. claude.ai blocks pages from calling Claude Code
  Remote's `send_message`.
- `tools/parse_events.py` prints a saved `list_events` result compactly, for
  reading another session's transcript.
- `tools/make_briefs.py` turns verified session profiles into
  `.claude/agents/<key>.md` briefs and roster rows.

The protocol agents follow is section 11 of `AGENTS.md`.
