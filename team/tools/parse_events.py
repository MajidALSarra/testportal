"""Print a list_events result (saved tool-result file or raw JSON) compactly.
Usage: python3 -I parse_events.py <file> [--full]
Prints cursor info first (first_id = pass as before_id to page OLDER), then each event:
  [HUMAN]   a person's message (full text)        [SEED/PEER] session-created or cross-session input
  [ASSISTANT text] Claude's prose                  [tool_use] name + input (truncated)
  [tool_result] truncated                          [RESULT] end-of-turn summary
"""
import json, sys, re
full = "--full" in sys.argv
raw = open(sys.argv[1]).read()
m = re.search(r'\{.*\}', raw, re.S)
d = json.loads(m.group(0))
root = d.get("ccr", d)
evts = root.get("data", [])
print(f"# events={len(evts)} has_more={root.get('has_more')} first_id={root.get('first_id')} last_id={root.get('last_id')}")
if evts:
    print(f"# span {evts[0].get('created_at','')[:19]} .. {evts[-1].get('created_at','')[:19]}")
LIM_T = 100000 if full else 4000
for e in evts:
    kind = next((k for k in ("user","assistant","result") if k in e), None)
    if not kind: continue
    body = e[kind]
    inner = body.get("internal_anthropic_catchall", body) if isinstance(body, dict) else {}
    ts = e.get("created_at","")[:16].replace("T"," ")
    if kind == "result":
        print(f"\n{ts} [RESULT subtype={inner.get('subtype')} error={inner.get('is_error')}]\n{str(inner.get('result',''))[:LIM_T]}")
        continue
    msg = inner.get("message", {}) or {}
    content = msg.get("content", "")
    origin = inner.get("inbound_origin") or inner.get("client_platform") or ""
    tag = "HUMAN" if kind == "user" else "ASSISTANT"
    if kind == "user" and origin and origin not in ("", "web_claude_ai", "android", "desktop_app", "claude_code_cli", "ios"):
        tag = f"SEED/PEER origin={origin}"
    if isinstance(content, str):
        if content.strip():
            print(f"\n{ts} [{tag}]\n{content[:LIM_T]}")
        continue
    for b in content:
        t = b.get("type")
        if t == "text" and b.get("text","").strip():
            print(f"\n{ts} [{tag}{' text' if kind=='assistant' else ''}]\n{b['text'][:LIM_T]}")
        elif t == "tool_use":
            print(f"{ts} [tool_use] {b.get('name')} {json.dumps(b.get('input'), ensure_ascii=False)[:400 if not full else 4000]}")
        elif t == "tool_result":
            c = b.get("content")
            s = c if isinstance(c, str) else json.dumps(c, ensure_ascii=False)
            print(f"{ts} [tool_result] {s[:300 if not full else 3000]}")
