# Reviewer demo PC (Magpie, infra)

A small Windows VM that ChatGPT's app reviewers reach through the Folderbird plugin: always online,
signed into a dedicated reviewer account, holding only fictional files and public-domain photos.
Context: `team/notes/chatgpt-review-2026-10-13.md`; Slack thread `1791869664.045449`;
review: `team/notes/demo-pc-review-2026-10-13.md` (branch `ccr-7c9a50bf-2n2cnk`).

## Status

**Created so far: nothing.** No Azure resource, no account, no spend. Waiting for Majid's typed go
(about $40-50 a month, plus the reviewer account). Every script parses in PowerShell 7.4.6 and is
ASCII-only; none has run on Windows or Azure yet.

## How to run (after the go)

It takes 20-40 minutes and cannot run inside a 45 s Folderbird `run_command`. Either Majid opens a
PowerShell window, or an agent starts it detached and polls the log:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\new-review-vm.ps1 -SubscriptionId <id> -AlertEmail <email> -WhatIf   # preflight only
.\new-review-vm.ps1 -SubscriptionId <id> -AlertEmail <email>           # build; re-run resumes by stage
# detached: Start-Process powershell.exe -ArgumentList '-NoExit','-ExecutionPolicy','Bypass','-File',
#   '<path>\new-review-vm.ps1','-SubscriptionId','<id>','-AlertEmail','<email>'
# log: %LOCALAPPDATA%\fb-review\build.log, last line BUILD:OK or BUILD:FAILED <step>
```

The script takes no password argument and asks for nothing. Never add a password parameter.

Order: preflight (subscription pinned, group must be new or ours, size available, files present) ->
resource group -> **budget alert** (read back) -> NSG -> VM -> Bastion Developer -> demo user ->
restart -> wait for profile + app -> documents -> photos -> **outbound lock** (checked). The VM's
`stage` tag (`created`, `user`, `seeded`, `locked`) lets a re-run resume, and a `locked` VM refuses
every in-VM step.

Then Majid: Portal > fb-review > Connect > Bastion, sign in as `.\fbreview` with the password the
window showed once (not in the log), sign the Folderbird app into the reviewer account, close the
Bastion tab without signing out, and check My Devices shows `fb-review` Connected.
After that: connector-smoke on prod with the reviewer account, then resubmit.

Remove it all: `az group delete -n folderbird-review-rg` (a deletion: needs Majid's go).

## Safety design

- Own resource group `folderbird-review-rg`; names matching cloudpc, build or `folderbird-rg` are refused,
  and an existing group without our `purpose` tag is refused.
- **No inbound allow rule** (the script stops if one exists). Bastion Developer uses Azure's platform
  address, already allowed by the default NSG rules.
- **Outbound lock after seeding.** Reviewers get a shell, and abuse from it would be billed and blamed
  on this subscription (it was suspended once, on 11 Oct). Outbound is allowed only to folderbird.com and
  the App Service host (resolved at build time), Azure Storage West Europe (file transfers), Windows Update,
  Microsoft Front Door and KMS activation; everything else to the Internet is denied, and a check proves
  folderbird.com works while example.com does not. If folderbird.com's IPs change, run `-RefreshEgress`.
  A separate subscription would isolate it further; Majid decides.
- The app runs as a **standard user**. The built-in admin account is disabled; its random password is
  never kept. Admin work is `az vm run-command` as SYSTEM.
- Passwords never touch a command line or the log: random, passed to az as `@file` (user-only ACL,
  deleted in `finally`), base64 inside the protected parameter. The managed run-command that carried it
  is deleted afterwards.
- `C:\ProgramData\FolderbirdDemo` is SYSTEM/Administrators-writable only; Autologon64.exe is deleted
  after use; signers are checked by exact name.
- Auto-logon (LSA secret) with ForceAutoLogon, and a task every 5 minutes that reinstalls/restarts the app.
- Photos: Commons files whose own metadata says CC0 or public domain, re-encoded; only GDI+'s structural
  JPEG tags may remain, anything else (EXIF, GPS) means the file is dropped.
- No managed identity (checked), no az/gh login, no keys, nothing of Majid's on the VM.

## Rules after the box is live

- **Never re-run `vm\*.ps1` as SYSTEM once reviewers have had access**: a reviewer can plant files or
  junctions where SYSTEM works. Rebuild the VM instead. The `locked` stage enforces this for the script.
- In the VM, sign in only with the reviewer account. Never sign Edge into a Microsoft or Google account;
  clear saved logins before closing Bastion. Reviewers can read everything in that session.

## Known risks

- App 1.2.7.0 can take longer than the 45 s MCP limit on some calls; 1.2.8.1 fixes it, not released.
- The outbound lock may block things Windows wants (some Defender or store updates).
- The budget amount is in the billing account's currency; its alerts end after 5 years.
