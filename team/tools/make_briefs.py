"""Turn verified session profiles into agent briefs and room roster rows.
Usage: python3 -I make_briefs.py <profiles.json> <roster.json> <repo_root> <out_rows.json>
profiles.json: workflow output list [{id, short, result:{profile, corrections, confidence}}]
roster.json:   {short: {key, name, color, order, role, role_title(optional override)}}
"""
import json, sys, pathlib, textwrap
prof_path, roster_path, repo_root, rows_out = sys.argv[1:5]
profiles = json.load(open(prof_path))
roster = json.load(open(roster_path))
ROOM = "https://claude.ai/artifact/MonDhz4FLkicysFNUeqTAh"
COORD = "session_01FmfGfufZrhoG771DieoNK8"
agents_dir = pathlib.Path(repo_root, ".claude", "agents"); agents_dir.mkdir(parents=True, exist_ok=True)

def bullets(items, empty="None recorded."):
    items = [str(i).strip() for i in (items or []) if str(i).strip()]
    return "\n".join(f"- {i}" for i in items) if items else f"- {empty}"

rows = []
team = []
for entry in profiles:
    r = roster[entry["short"]]
    res = entry.get("result") or {}
    p = res.get("profile") or {}
    key, name = r["key"], r["name"]
    role = r.get("role") or p.get("suggested_role", "")
    role_title = r.get("role_title") or p.get("role_title", "")
    repos = p.get("repos") or []
    repo_lines = [f"`{x.get('repo','')}` on `{x.get('branch','')}`: {x.get('purpose','')}" for x in repos]
    qs = p.get("open_questions_for_user") or []
    q_lines = [f"**{q.get('question','').strip()}** {q.get('context','').strip()} Recommendation: {q.get('recommendation','').strip()}" for q in qs]
    m_lines = [f"`{m.get('name','')}`: {m.get('use','')} Running now: {m.get('busy_now','')}" for m in (p.get("machines") or [])]
    desc = f"{name}, Folderbird's {role_title or role}. {p.get('headline','').rstrip('.')}. Use for work in this area or to resume it from session {entry['id']}."
    desc = desc.replace("\n", " ").replace('"', "'")
    body = f"""---
name: {key}
description: "{desc}"
---
You are **{name}**, the Folderbird team's {role_title or role}. Your role in AGENTS.md terms is `{role}`.
Your home session is `{entry['id']}` ("{r.get('title','')}"), and the coordinator is `{COORD}`.

## What you own

{p.get('headline','')}

{p.get('summary','')}

## Where the work stood on 2026-10-11

This is a snapshot taken from your session's transcript and checked by a second reader. Live state is in the team room, not here.

{p.get('current_state','')}

Repos and branches:
{bullets(repo_lines)}

Done:
{bullets(p.get('completed'))}

In flight:
{bullets(p.get('in_flight'))}

Waiting on Majid when the snapshot was taken:
{bullets(q_lines, 'Nothing.')}

Machines:
{bullets(m_lines, 'None.')}

## Corrections from other agents

{bullets(r.get('notes'), 'None yet.')}

## Durable facts

{bullets(p.get('key_facts'))}

## How Majid wants you to work

{p.get('working_style','')}

## Team room

You are a member of the Folderbird Team Room: {ROOM}
Post there as `{key}` and follow AGENTS.md section 11 for the message format, waking other agents, and questions for Majid.

## Taking over in a fresh session

If your home session is gone or out of context, a new session becomes you by reading this file and the last 50 room messages, then posting `online` with `from: "{key}"` and updating `agents/{key}.session_id` in the room to the new session id.
"""
    (agents_dir / f"{key}.md").write_text(body)
    rows.append({"key": key, "data": {
        "name": name, "role": role, "role_title": role_title,
        "headline": p.get("headline", ""), "session_id": entry["id"],
        "repos": [f"{x.get('repo','').split('/')[-1]} · {x.get('branch','')}" for x in repos][:6],
        "color": r["color"], "order": r["order"],
        "status_text": "", "brief": f".claude/agents/{key}.md in MajidALSarra/testportal",
    }})
    team.append({"key": key, "name": name, "role": role, "role_title": role_title, "session": entry["id"],
                 "title": r.get("title", ""), "headline": p.get("headline", ""), "confidence": res.get("confidence"),
                 "n_corrections": len(res.get("corrections") or []), "open_questions": len(qs)})
json.dump({"rows": rows, "team": team}, open(rows_out, "w"), indent=1, ensure_ascii=False)
for t in team: print(json.dumps(t, ensure_ascii=False))
