# Reviewer demo PC (Magpie, infra)

A small Windows VM that ChatGPT's app reviewers can reach through the Folderbird plugin: always online,
signed into a dedicated reviewer account, holding only fictional files and public-domain photos.
Context: `team/notes/chatgpt-review-2026-10-13.md`; Slack thread `1791869664.045449`.

## Status

**Created so far: nothing.** No Azure resource, no account, no spend. These files are a prepared plan
waiting for Majid's typed go (cost about $40-50 a month, plus the reviewer account).

| Piece | State |
|---|---|
| `seed/make_seed_files.py` + `seed/seed-docs.zip` | Built and checked: 12 fictional files (pdf, docx, xlsx, pptx, txt) |
| `vm/setup-user.ps1` | Written, parses (pwsh 7.4.6); not run anywhere |
| `vm/seed-docs.ps1`, `vm/seed-photos.ps1` | Written, parse; not run anywhere |
| `new-review-vm.ps1` | Written, parses; not run anywhere |
| Reviewer account `openai-review@folderbird.com` | Not created (decision for Majid) |

## Design

- Own resource group `folderbird-review-rg`, West Europe. Not cloudpc, not fb-build, nothing in `folderbird-rg`.
- Windows Server 2022, Standard_B2s, 64 GB Standard SSD. Linux was rejected: the Linux app breaks
  `write_file`/`upload_file` paths, which fails a reviewer test case.
- No inbound ports. The NSG has no allow rule; the script stops if one appears. Admin work runs through
  `az vm run-command` as SYSTEM. Majid reaches the desktop once through Bastion Developer (free).
- Admin account password is random and thrown away. The app runs as a STANDARD user `fbreview`
  (reviewers get a shell through the exec scope, so it must not be an administrator).
- Auto-logon through Sysinternals Autologon (LSA secret, not a plain-text registry value), so the
  app comes back after every restart. A logon task installs Folderbird (signed setup, signer checked)
  and starts it if it is not running.
- Photos come from Wikimedia Commons, only files whose own metadata says CC0 or public domain, and each
  is re-encoded so EXIF and GPS are gone; `Pictures\CREDITS.txt` lists the sources.
- Budget alert at 50/80/100 % of $60 a month (plus a 100 % forecast alert). No auto-shutdown.
- Nothing of Majid's goes on the VM: no az or gh login, no keys, no managed identity.

## Running it (after the go)

On the laptop, in a visible PowerShell window (it asks for the demo-user password, masked):

```powershell
Set-ExecutionPolicy -Scope Process Bypass
cd <testportal>\team\demo-pc
.\new-review-vm.ps1 -AlertEmail <owner email> -WhatIf   # plan only
.\new-review-vm.ps1 -AlertEmail <owner email>
```

Then Majid: Bastion into the VM as `.\fbreview`, sign the Folderbird app into the reviewer account,
close the Bastion tab (do not sign out of Windows), and check My Devices shows `fb-review` Connected.
After that: connector-smoke on prod with the reviewer account, then resubmit.

Remove it all: `az group delete -n folderbird-review-rg` (a deletion, so it needs Majid's go).

## Known risks

- App 1.2.7.0 can take longer than the 45 s MCP limit on some calls; 1.2.8.1 fixes it but is not released.
- Windows may not auto-logon after some restarts (seen on cloudpc). Check the device is online after any restart.
- Seed-docs travels in about 9 run-command calls (20,000-character chunks).
