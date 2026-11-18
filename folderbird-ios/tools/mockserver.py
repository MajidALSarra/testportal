#!/usr/bin/env python3
"""A stand-in for the Folderbird /api/v1 server, for the XCUITest screenshot run (FolderbirdUITests).

It answers the endpoints the iOS app calls with a fictional fleet (HOME-DESKTOP online, OFFICE-LAPTOP slow,
WORKSHOP-PC offline, HOME-NAS a Linux box) and a small fake file system, so the whole journey — sign-in, devices,
browse, preview (text / image / PDF / Office), search, upload, new folder, console incl. the destructive-command
refusal — can be driven with no credentials and no real PC. Nothing here talks to folderbird.com.

    python3 tools/mockserver.py --port 8787

Any key starting with "fbk_" is accepted, except one containing "wrong" (-> 401, like a revoked key).
"""
import argparse, json, re, struct, sys, time, zlib, uuid, threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs, unquote

PORT = 8787
LOCK = threading.Lock()

DEVICES = [
    {"id": 1, "name": "HOME-DESKTOP", "status": "online", "lastSeen": "just now", "appVersion": "1.2.8.1"},
    {"id": 2, "name": "OFFICE-LAPTOP", "status": "slow", "lastSeen": "2 min ago", "appVersion": "1.2.7.0"},
    {"id": 3, "name": "WORKSHOP-PC", "status": "offline", "lastSeen": "3 days ago", "appVersion": "1.2.7.0"},
    {"id": 4, "name": "HOME-NAS", "status": "online", "lastSeen": "just now", "appVersion": "0.2.2"},
]
OFFLINE = {3}
POSIX = {4}

# ── fake content ────────────────────────────────────────────────────────────

NOTES = """Folderbird — notes.txt (mock)

Shopping
- milk, eggs, dates
- printer paper

Project
- send the Q3 report to Sara
- renew the domain before 1 Dec
- back up the photos folder

This file lives on the PC; the phone only shows a copy fetched on demand.
"""

def make_png(w=640, h=400):
    """A sunset gradient with a sun — pure Python, no Pillow."""
    raw = bytearray()
    for y in range(h):
        raw.append(0)
        t = y / (h - 1)
        for x in range(w):
            r = int(255 * (0.95 - 0.55 * t)); g = int(255 * (0.55 - 0.35 * t)); b = int(255 * (0.25 + 0.25 * t))
            dx, dy = x - w * 0.62, y - h * 0.42
            if dx * dx + dy * dy < 60 * 60:
                r, g, b = 255, 236, 150
            if y > h * 0.72:
                r, g, b = int(r * 0.35), int(g * 0.35), int(b * 0.55)
            raw += bytes((r, g, b))
    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xffffffff)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(bytes(raw), 6)) + chunk(b"IEND", b""))

def make_pdf():
    """A one-page PDF with a title and three lines; xref offsets computed, so PDFKit accepts it."""
    content = b"""BT /F1 28 Tf 60 740 Td (Annual Report 2026) Tj ET
BT /F1 14 Tf 60 700 Td (Folderbird mock document - rendered by PDFKit on the phone.) Tj ET
BT /F1 14 Tf 60 676 Td (Revenue up 18%, three new regions, zero downtime.) Tj ET
BT /F1 14 Tf 60 652 Td (The file never left the PC until you tapped it.) Tj ET
60 620 m 540 620 l S
"""
    objs = [
        b"<< /Type /Catalog /Pages 2 0 R >>",
        b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>",
        b"<< /Length " + str(len(content)).encode() + b" >>\nstream\n" + content + b"endstream",
        b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    ]
    out = bytearray(b"%PDF-1.4\n")
    offsets = []
    for i, o in enumerate(objs, 1):
        offsets.append(len(out))
        out += f"{i} 0 obj\n".encode() + o + b"\nendobj\n"
    xref = len(out)
    out += f"xref\n0 {len(objs) + 1}\n0000000000 65535 f \n".encode()
    for off in offsets:
        out += f"{off:010d} 00000 n \n".encode()
    out += f"trailer\n<< /Size {len(objs) + 1} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n".encode()
    return bytes(out)

PNG = make_png()
PDF = make_pdf()
CSV = "month,revenue,expenses\nJan,120000,80000\nFeb,135000,82000\nMar,150000,90000\n"

def office_blob(name):
    return ("PK\x03\x04 mock office file: " + name).encode()

FILES = {}      # id -> {normpath: {"folders": [...], "files": [...]} }
BLOBS = {}      # (id, normpath) -> bytes

def norm(dev, p):
    p = (p or "").strip()
    if dev in POSIX:
        p = re.sub(r"/+", "/", p.replace("\\", "/"))
        if len(p) > 1: p = p.rstrip("/")
        return p or "/"
    p = p.replace("/", "\\")
    p = re.sub(r"\\+", "\\\\", p)
    if len(p) > 3: p = p.rstrip("\\")
    if re.fullmatch(r"[A-Za-z]:", p): p += "\\"
    return p.lower()

def join(dev, folder, name):
    if dev in POSIX:
        return (folder.rstrip("/") + "/" + name) if folder != "/" else "/" + name
    return folder.rstrip("\\") + "\\" + name

def add_folder(dev, path, folders=(), files=()):
    FILES.setdefault(dev, {})[norm(dev, path)] = {
        "path": path,
        "folders": [{"name": f, "path": join(dev, path, f)} for f in folders],
        "files": [{"name": n, "size": s, "lastmodified": m} for (n, s, m) in files],
    }

def seed():
    home = "C:\\Users\\Alex"
    add_folder(1, "C:\\", ["Program Files", "Users", "Windows"], [("pagefile.sys", 4294967296, "2026-11-01 08:00")])
    add_folder(1, "C:\\Users", ["Alex", "Public"])
    add_folder(1, home, ["Desktop", "Documents", "Downloads", "Music", "Pictures", "Videos"],
               [("todo.md", 812, "2026-11-17 22:10")])
    add_folder(1, home + "\\Documents", ["Receipts", "Tax 2026"], [
        ("Annual-Report-2026.pdf", len(PDF), "2026-10-02 14:33"),
        ("Project-Report-Draft.docx", 48213, "2026-11-15 09:12"),
        ("Q3-Sales-Report.xlsx", 23890, "2026-10-28 17:45"),
        ("Report-Template.pptx", 1240331, "2026-09-30 11:02"),
        ("budget.csv", len(CSV.encode()), "2026-11-10 19:21"),
        ("notes.txt", len(NOTES.encode()), "2026-11-18 07:58"),
    ])
    add_folder(1, home + "\\Documents\\Receipts", [], [("receipt-ikea.pdf", 88213, "2026-11-03 13:00")])
    add_folder(1, home + "\\Documents\\Tax 2026", [], [])
    add_folder(1, home + "\\Pictures", ["Camera Roll"], [
        ("sunset.png", len(PNG), "2026-11-12 18:40"),
        ("family-dinner.jpg", 3812211, "2026-11-08 20:15"),
    ])
    add_folder(1, home + "\\Pictures\\Camera Roll", [], [("IMG_0231.jpg", 2910211, "2026-11-16 12:01")])
    add_folder(1, home + "\\Downloads", [], [("Folderbird-Setup-1.2.8.1.exe", 2812934, "2026-11-14 10:30")])
    for f in ("Desktop", "Music", "Videos"):
        add_folder(1, home + "\\" + f, [], [])
    add_folder(1, "D:\\", ["Backups", "Games"], [])
    BLOBS[(1, norm(1, home + "\\Documents\\notes.txt"))] = NOTES.encode()
    BLOBS[(1, norm(1, home + "\\Documents\\budget.csv"))] = CSV.encode()
    BLOBS[(1, norm(1, home + "\\Documents\\Annual-Report-2026.pdf"))] = PDF
    BLOBS[(1, norm(1, home + "\\Pictures\\sunset.png"))] = PNG
    BLOBS[(1, norm(1, home + "\\todo.md"))] = b"# todo\n\n- [x] install Folderbird\n- [ ] test the iPad app\n"
    # the same tree on the slow laptop, so it can be opened too
    FILES[2] = FILES[1]
    # a Linux box
    add_folder(4, "/", ["etc", "home", "srv", "var"], [])
    add_folder(4, "/home", ["alex"], [])
    add_folder(4, "/home/alex", ["media", "projects"], [("README.md", 310, "2026-11-01 09:00")])
    add_folder(4, "/home/alex/media", [], [("sunset.png", len(PNG), "2026-11-12 18:40")])
    add_folder(4, "/home/alex/projects", ["folderbird"], [])
    BLOBS[(4, "/home/alex/README.md")] = b"# alex's NAS\n\nMedia and project files.\n"
    BLOBS[(4, "/home/alex/media/sunset.png")] = PNG

seed()
TOKENS = {}   # token -> (dev, normpath, name)

DESTRUCTIVE = {"del", "erase", "rd", "rmdir", "rm", "remove-item", "move-item", "mv", "format", "diskpart",
               "shutdown", "stop-process", "taskkill", "kill", "restart-computer"}

def exec_output(dev, cmd, shell):
    c = cmd.strip()
    low = c.lower()
    name = next(d["name"] for d in DEVICES if d["id"] == dev)
    if low == "hostname": return name
    if low == "whoami": return f"{name.lower()}\\alex"
    if low in ("ver", "winver"): return "Microsoft Windows [Version 10.0.26100.2314]"
    if low.startswith("dir") or low.startswith("ls"):
        return (" Volume in drive C has no label.\n Directory of C:\\Users\\Alex\n\n"
                "18/11/2026  07:58    <DIR>          Documents\n18/11/2026  07:58    <DIR>          Pictures\n"
                "17/11/2026  22:10               812 todo.md\n               1 File(s)            812 bytes\n")
    if low.startswith("get-process"):
        return ("Handles  NPM(K)    PM(K)      WS(K)     CPU(s)     Id  SI ProcessName\n"
                "-------  ------    -----      -----     ------     --  -- -----------\n"
                "    412      22    48120      61244       3.14   8820   1 FolderbirdClient\n"
                "   1842      61   220144     198320      44.20   1220   1 chrome\n")
    if low.startswith("echo "): return c[5:]
    if low == "date" or low == "get-date": return time.strftime("%A, %d %B %Y %H:%M:%S")
    return f"(mock {shell}) ran: {c}"

def first_token(cmd):
    c = cmd.strip()
    for sep in ("&&", "||", "|", ";", "&"):
        c = c.split(sep)[0]
    t = c.strip().split()
    return t[0].lower().strip('"\'') if t else ""

class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        sys.stdout.write("%s %s\n" % (time.strftime("%H:%M:%S"), fmt % args)); sys.stdout.flush()

    # ── helpers ──
    def send_json(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def send_bytes(self, code, data, ctype, name=None):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        if name: self.send_header("Content-Disposition", f'attachment; filename="{name}"')
        self.end_headers()
        self.wfile.write(data)

    def body(self):
        n = int(self.headers.get("Content-Length") or 0)
        return self.rfile.read(n) if n else b""

    def authed(self):
        a = self.headers.get("Authorization", "")
        key = a[7:].strip() if a.lower().startswith("bearer ") else ""
        if not key.startswith("fbk_") or "wrong" in key:
            self.send_json(401, {"error": "Invalid or revoked API key"})
            return False
        return True

    def device(self, raw):
        try: dev = int(unquote(raw))
        except ValueError: dev = -1
        if not any(d["id"] == dev for d in DEVICES):
            self.send_json(404, {"error": "Device not found"}); return None
        if dev in OFFLINE:
            time.sleep(1.0)
            self.send_json(504, {"error": "Device did not respond within 30s"}); return None
        return dev

    # ── routing ──
    def do_GET(self):
        u = urlparse(self.path); q = parse_qs(u.query)
        p = u.path
        if p == "/healthz": return self.send_bytes(200, b"ok", "text/plain")
        if p.startswith("/preview/"):
            tok = p.split("/")[2]
            name = TOKENS.get(tok, (0, "", "file"))[2]
            html = f"""<!doctype html><html><body style="font-family:-apple-system;padding:24px;color:#0B0F12">
<h2 style="margin:0 0 8px">{name}</h2><p style="color:#555">Server-rendered preview page (mock). On the real server this page renders Office files with PPTXjs / docx-preview / SheetJS.</p>
<table border="1" cellpadding="8" style="border-collapse:collapse;margin-top:16px"><tr><th>Quarter</th><th>Revenue</th></tr><tr><td>Q1</td><td>405,000</td></tr><tr><td>Q2</td><td>462,000</td></tr><tr><td>Q3</td><td>518,000</td></tr></table></body></html>"""
            return self.send_bytes(200, html.encode(), "text/html; charset=utf-8")
        if not self.authed(): return
        if p == "/api/v1/devices":
            return self.send_json(200, {"devices": DEVICES})
        m = re.fullmatch(r"/api/v1/files/([A-Za-z0-9]+)", p)
        if m:
            t = TOKENS.get(m.group(1))
            if not t: return self.send_json(404, {"error": "Link expired"})
            return self.send_file(t[0], t[1], t[2])
        m = re.fullmatch(r"/api/v1/devices/([^/]+)/(system|files|search|files/download)", p)
        if not m: return self.send_json(404, {"error": "Not found"})
        dev = self.device(m.group(1))
        if dev is None: return
        what = m.group(2)
        if what == "system":
            if dev in POSIX:
                return self.send_json(200, {"host": "HOME-NAS", "home": "/home/alex",
                                            "disks": [{"drive": "/", "freeGB": 1402.3, "totalGB": 3726.0}]})
            return self.send_json(200, {"host": "HOME-DESKTOP", "home": "C:\\Users\\Alex",
                                        "disks": [{"drive": "C:", "freeGB": 412.5, "totalGB": 931.5},
                                                  {"drive": "D:", "freeGB": 1802.1, "totalGB": 1863.0}]})
        path = (q.get("path") or [""])[0]
        if what == "files":
            entry = FILES.get(dev, {}).get(norm(dev, path))
            if not entry: return self.send_json(404, {"error": f"Folder not found: {path}"})
            name = next(d["name"] for d in DEVICES if d["id"] == dev)
            return self.send_json(200, {"device": name, "path": entry["path"], "folders": entry["folders"], "files": entry["files"]})
        if what == "files/download":
            return self.send_file(dev, norm(dev, path), path.replace("\\", "/").rsplit("/", 1)[-1])
        if what == "search":
            needle = (q.get("q") or [""])[0].lower()
            scope = norm(dev, (q.get("scope") or [""])[0]) if q.get("scope") else ""
            res = []
            for np_, entry in FILES.get(dev, {}).items():
                if scope and not np_.startswith(scope): continue
                for f in entry["files"]:
                    if needle in f["name"].lower():
                        res.append({"path": join(dev, entry["path"], f["name"]), "size": f["size"], "modified": f["lastmodified"]})
            time.sleep(0.4)
            return self.send_json(200, {"count": len(res), "results": res})

    def send_file(self, dev, npath, name):
        data = BLOBS.get((dev, npath))
        if data is None:
            data = office_blob(name) if name.lower().endswith((".docx", ".xlsx", ".pptx", ".xls")) else b"mock bytes of " + name.encode()
        ct = {"png": "image/png", "pdf": "application/pdf", "txt": "text/plain", "csv": "text/csv", "md": "text/markdown"}.get(
            name.lower().rsplit(".", 1)[-1], "application/octet-stream")
        return self.send_bytes(200, data, ct, name)

    def do_POST(self):
        u = urlparse(self.path); q = parse_qs(u.query); p = u.path
        raw = self.body()
        if not self.authed(): return
        if p == "/api/v1/devices/code":
            return self.send_json(200, {"code": "7K3P-Q9ZX", "minutes": 10, "required": True})
        m = re.fullmatch(r"/api/v1/devices/([^/]+)/(exec|files/preview|files/upload|files/write|folders)", p)
        if not m: return self.send_json(404, {"error": "Not found"})
        dev = self.device(m.group(1))
        if dev is None: return
        what = m.group(2)
        name = next(d["name"] for d in DEVICES if d["id"] == dev)
        path = (q.get("path") or [""])[0]
        if what == "exec":
            try: obj = json.loads(raw.decode() or "{}")
            except ValueError: obj = {}
            cmd = str(obj.get("command", "")); shell = str(obj.get("shell", "cmd"))
            if first_token(cmd) in DESTRUCTIVE and obj.get("confirmDestructive") is not True:
                return self.send_json(409, {"error": "This command can delete, move or change system state and was NOT run. "
                                                     "Show the user the exact command, ask them to confirm it, and re-send it with confirmDestructive true.",
                                            "code": "confirm_destructive_required", "device": name, "verb": first_token(cmd)})
            time.sleep(0.6)
            out = exec_output(dev, cmd, shell) if obj.get("confirmDestructive") is not True else f"(mock) confirmed and ran: {cmd}"
            return self.send_json(200, {"device": name, "shell": shell, "command": cmd, "output": out})
        if what == "files/preview":
            tok = uuid.uuid4().hex
            fname = path.replace("\\", "/").rsplit("/", 1)[-1]
            TOKENS[tok] = (dev, norm(dev, path), fname)
            host = self.headers.get("Host", f"127.0.0.1:{PORT}")
            size = len(BLOBS.get((dev, norm(dev, path)), b"")) or 1024
            return self.send_json(200, {"file": fname, "size": size, "preview_url": f"http://{host}/preview/{tok}",
                                        "download_url": f"http://{host}/api/v1/files/{tok}", "expires": "15 minutes"})
        if what == "folders":
            parent = norm(dev, path.replace("/", "\\").rsplit("\\", 1)[0] if dev not in POSIX else path.rsplit("/", 1)[0] or "/")
            fname = path.replace("\\", "/").rsplit("/", 1)[-1]
            with LOCK:
                entry = FILES.get(dev, {}).get(parent)
                if not entry: return self.send_json(404, {"error": "Parent folder not found"})
                if any(f["name"].lower() == fname.lower() for f in entry["folders"]):
                    return self.send_json(200, {"ok": True, "created": False, "existed": True})
                entry["folders"].append({"name": fname, "path": path})
                add_folder(dev, path, [], [])
            return self.send_json(200, {"ok": True, "created": True, "existed": False})
        if what == "files/write":
            try: content = json.loads(raw.decode() or "{}").get("content", "")
            except ValueError: content = ""
            return self.put_file(dev, path, content.encode())
        if what == "files/upload":
            mm = re.search(rb'filename="([^"]*)"', raw)
            fname = mm.group(1).decode(errors="replace") if mm else "upload.bin"
            data = b""
            if mm:
                start = raw.find(b"\r\n\r\n", mm.end())
                ctype = self.headers.get("Content-Type", "")
                bm = re.search(r"boundary=([^;]+)", ctype)
                end = raw.find(b"\r\n--" + bm.group(1).strip('"').encode(), start) if bm else -1
                data = raw[start + 4:end if end > 0 else len(raw)]
            return self.put_file(dev, join(dev, path, fname), data)

    def put_file(self, dev, full, data):
        folder = full.replace("/", "\\").rsplit("\\", 1)[0] if dev not in POSIX else (full.rsplit("/", 1)[0] or "/")
        fname = full.replace("\\", "/").rsplit("/", 1)[-1]
        with LOCK:
            entry = FILES.get(dev, {}).get(norm(dev, folder))
            if not entry: return self.send_json(404, {"error": "Folder not found"})
            entry["files"] = [f for f in entry["files"] if f["name"].lower() != fname.lower()]
            entry["files"].append({"name": fname, "size": len(data), "lastmodified": time.strftime("%Y-%m-%d %H:%M")})
            BLOBS[(dev, norm(dev, full))] = data
        time.sleep(0.5)
        return self.send_json(200, {"ok": True, "file": fname, "size": len(data)})

if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=8787)
    ap.add_argument("--bind", default="127.0.0.1")
    a = ap.parse_args()
    PORT = a.port
    srv = ThreadingHTTPServer((a.bind, a.port), H)
    print(f"mock folderbird api on http://{a.bind}:{a.port}", flush=True)
    srv.serve_forever()
