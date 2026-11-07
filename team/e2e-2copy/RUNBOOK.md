# Two-copy staging test: setup and cleanup runbook

Goal: one new throwaway account on the STAGING slot, the GitHub secrets E2E_PASSWORD and E2E_API_KEY, and two
temporary test devices signed into it, so that staging-e2e.yml and staging-api-e2e.yml can run the two-instance test:

| Device (site name) | What | Where | Address |
|---|---|---|---|
| E2E2C-LNX | Linux app 0.2.2 (public beta tarball, hash-checked) | Azure Container Instance fb-e2e2c-linux | 02e2e2c00001 |
| E2E2C-WIN | Windows app 1.2.8.1 (published signed zip), test-profile mode | throwaway VM fb-e2e2c-win | 02E2E2C00002 |

Both live in resource group folderbird-e2e-rg (westeurope, tag purpose=e2e-2copy); one group delete removes them.
Reference source: folderbird-web main 91de08d, folderbird-agent main 1f14100.

Nothing here has been run on Windows. Every .ps1 parses with the pwsh 7.4.6 parser and passes the repo's reserved-name
scanner, and the files are ASCII only. b0, b2, e2, t-device-token, c1 and v4 were run under pwsh 7 against fake
servers; a2, a4 and e2 were run again under pwsh 7 against a fake az and fake sign-ins after the abort/sticky-list
changes. Windows PowerShell 5.1 itself and the real Azure/GitHub/staging calls are untested.

## How to run (all steps)

- **Where:** the laptop (device 39), through Folderbird run_command/write_file. It is the only place secrets exist.
- **Shell:** every inline command in this runbook is PowerShell. Call `mcp__Folderbird__run_command` with
  `shell='powershell'` every time (E6 included); the default is cmd, where `Start-Process`, `Get-Content` and
  `Remove-Item` do not exist, so nothing starts and no log is written.
- **Setup:** first run `New-Item -ItemType Directory -Force C:\Temp\e2e | Out-Null; 'ok'`, then write_file every file
  of this folder to `C:\Temp\e2e\<same name>`. They are ASCII; the .ps1 files use CRLF.
- **Start a script detached**, because run_command stops after 45 s:
  `Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','C:\Temp\e2e\<script>.ps1'[,'-Param','value']; 'started'`
- **Read the result:** `Get-Content C:\Temp\e2e\<script>.log -Tail 40`. Every log ends in DONE or
  `FAILED line N: <real cause>`, followed by a `stack:` line. az/gh stderr goes to `<script>.err`, redacted.
- **Rules:**
  - Never Get-Content pw.txt, bootstrap.txt, apikey.txt, *-token.txt, vm-admin.txt or old-testaccount.json.
  - Never add your own 2>&1.
  - End inline commands with `'ok'`, never with `}`.
- **What the scripts do for you:**
  - Every script that touches a secret first proves C:\Temp\e2e is closed to everyone but this user and SYSTEM (by SID).
  - Secrets reach az, gh and the VM only as files or stdin.
  - Logs carry lengths, names and hashes only.
- **Tags in the steps below:**
  - [PROD-SHARED] = writes the database, Redis or Blob storage that production also uses.
  - [SPEND] = Azure cost.
  - Nothing in sections 0 to E contacts the production host except the VM's one GET of
    https://folderbird.com/download/windows. Section P deliberately moves both test PCs and both workflows to the
    production host (Majid, 7 Nov 09:03 Riyadh).
- **Approvals:**
  - Majid's go before C1 and V1 [SPEND], and before every E step (deletions).
  - Tell Falcon before A2 and A4 (staging restarts; production untouched). Neither writes the site-wide sticky-name
    list that production shares (A2 refuses up front when A4 would have to; A4 checks the list before and after).
  - Send Kestrel the D2 inputs.
  - The destructive-command gate does not see inside a script started with Start-Process, so the go is still needed.

## 0. Preflight (read-only)

1. Run `mcp__Folderbird__list_devices` and confirm the laptop is online. Post the start in #folderbird-agents.
2. Run `p0-preflight.ps1`.
   - **Check that it logs:**
     - the az version and account;
     - staging and production instance names. Keep production's ids: E5 compares them. They come from ARM; the
       production host is never contacted.
     - staging TestAccount__* names, stickiness and the seeded address;
     - the site-wide sticky app-setting names (shared with production; names only). E5 must show the same list.
     - whether folderbird-e2e-rg exists;
     - quota;
     - the gh path and auth exit code, repo secret names, and the last 3 runs of both e2e workflows;
     - free space on C:;
     - staging /healthz/ready;
     - which secret files already exist.
   - **Stop if any of these is true:**
     - gh is NOT FOUND, or az does not answer.
     - A staging-e2e or staging-api-e2e run is in progress or queued.
     - E2E_PASSWORD or E2E_API_KEY exist and someone else may be using them. Overwriting cannot be undone; ask Kestrel.
     - folderbird-e2e-rg exists without being from this procedure.
     - pw.txt or apikey.txt already hold a value.

## A. Test account (password never in App Service)

| Step | Script | Touches | Check that proves it | Stop if |
|---|---|---|---|---|
| A1 | `a1-account.ps1` (`-Email e2e-2copy-b@folderbird.com` only if A3 says the address is taken) | laptop files only | `locked: inheritance off, only <SID> and S-1-5-18`; `pw.txt and bootstrap.txt written: 32 and 32 chars`; DONE | icacls or the ACL check fails; a password file already holds a value |
| A2 | `a2-seed-settings.ps1` (tell Falcon first) | [PROD-SHARED] staging app settings get the address + the BOOTSTRAP value via `--settings @file` (values only; stickiness untouched); staging restarts, runs the schema batch, seeder writes one AspNetUsers row | `before:` lines (old names, stickiness, address); the sticky-name line; `old-testaccount.json written`; `after: TestAccount__Email = <ours>`; DONE | set fails; staging previously seeded something unexpected (WARNING line); `... is in the site-wide sticky list` (nothing was changed: ask Falcon/Majid) |
| A3 | `q-seed.ps1` (~1 min after A2; runs up to ~25 min) | read-only (staging health + Log Analytics) | `staging ready`; `seeder| ... created pre-verified account <ours>` (Where=staging); `VERDICT: account created` | `marked email-confirmed` (someone registered the address: **abort sequence**, skipping E2, then A1 `-Email e2e-2copy-b@folderbird.com`); `FAILED to create` with no created line (password rule: abort sequence) |
| B0 | `b0-set-password.ps1` | [PROD-SHARED] the account's password hash: bootstrap -> pw.txt via /Manage/ChangePassword | `password changed ... ChangePasswordSuccess`; `sign-in with pw.txt in a fresh session: ok`; `bootstrap.txt blanked`; DONE | the bootstrap value AND pw.txt both refused (account not ours / not created): abort sequence |
| A4 | `a4-restore-settings.ps1` right after B0 (tell Falcon) | [PROD-SHARED] staging restarts again; old TestAccount__* values put back with `--settings` (ours deleted if staging had none; BLANKED instead if the name is in the site-wide sticky list, because `appsettings delete` would also drop it from production's list) | `site-wide sticky list unchanged`; `now:` lines equal the `before:` lines (checked by the script); `TestAccount__Email = <old address>`; `old-testaccount.json blanked`; DONE; then staging /healthz/ready is ready | any mismatch (the script refuses DONE); `sticky list CHANGED` (tell Falcon at once) |

**Abort sequence** (the way back when setup stops after A2: q-seed or B0 says stop, staging trouble, or Majid stops it).
Run in the SAME folder, never a fresh one: old-testaccount.json is the only copy of staging's original TestAccount__*
values (e2e-staging, used by connector-smoke and staging-e2e).
1. `a4-restore-settings.ps1 -Abort` (tell Falcon; staging restarts). `-Abort` only skips the "B0 done" check. Check the
   `now:` lines equal A2's `before:` lines and `old-testaccount.json blanked`; DONE.
2. E1, if C1 or V1 ran.
3. E2, except when q-seed reported `marked email-confirmed` (that account is someone else's). With bootstrap.txt still
   holding a value, E2 also tries the bootstrap value, deletes the account with whichever signs in, and requires BOTH
   to be refused afterwards.
4. E3, if B1 or B3 ran.
5. E4 (it refuses while old-testaccount.json still holds a value), then E5 and E6 as in section E.
To start again afterwards: A1 in the same folder once E4 is DONE (or a new folder after E6).

Notes:
- **Two instances:** if staging runs two instances, the second may log `FAILED to create ... is already taken` or
  `error (startup continues)`. That is harmless when a `created` line exists.
- **What App Service ends up holding:** after B0, the value in App Service, in its config snapshots and in anything
  that read it (connector-smoke reads TestAccount__Password) is a dead password.

## B. GitHub secrets and the API key

| Step | Script | Touches | Check | Stop if |
|---|---|---|---|---|
| B1 | `b-set-secret.ps1 -Secret E2E_PASSWORD` (only after B0 DONE) | GitHub repo secret, value fed to `gh secret set` on stdin | `gh secret set E2E_PASSWORD: exit 0 (32 chars ...)` and a fresh `gh secret list` line | gh exit not 0 |
| B2 | `b2-mint-key.ps1` (after C1 AND C2 are online) | [PROD-SHARED] one ApiKeys row; the previous key in apikey.txt is revoked first | `device on the account:` both names; `key ... 52 chars, 1 day, device ids <win>,<lnx>`; `the key sees:` exactly E2E2C-LNX and E2E2C-WIN; DONE | either device missing or duplicated; key not shown (TempData lost: revoke the named row by hand on /Manage/ApiKeys) |
| B3 | `b-set-secret.ps1 -Secret E2E_API_KEY` | GitHub repo secret | as B1 | as B1 |

Key details:
- **Scope:** the key is bound to the two test devices (deviceScope=selected). Its scopes are devices:read, browse,
  download, upload and exec, exactly what staging-api-e2e uses.
- **Lifetime:** 24 h. If testing runs longer, run B2 and B3 again.

## C1. Linux 0.2.2 in Azure Container Instances  [SPEND about $0.06/h, Majid's go]

| Step | Script | Touches | Check | Stop if |
|---|---|---|---|---|
| C1a | `t-device-token.ps1 -Device lnx` | [PROD-SHARED] Devices row E2E2C-LNX (platform linux), Redis presence | `signed in E2E2C-LNX (02e2e2c00001) ... token N chars` | LoginFailed/LockedOut/DeviceLimitReached (printed), HTTP 429 (wait 60 s) |
| C1b | `c1-linux-aci.ps1` (`-Recreate` to replace an existing container, after a new C1a) | [SPEND] rg folderbird-e2e-rg (created with the tag, or accepted only with it) + container group; [PROD-SHARED] the device polls staging (or production with `-Target production`, section P) | `attempt 1 ...`; `lnx-token.txt blanked`; `container: Running`; DONE | 3 failed creates (read c1-linux-aci.err) |
| C1c | `aci-logs.ps1` (2-3 min later; also inline) | read-only | `aci| /tmp/fb.tgz: OK`; `token file written: N bytes`; `connected`; `VERDICT: archive hash True; token file True; connected True`; two `linux E2E2C-LNX` lines in hashes.txt | hash mismatch: stop and report (the published blob changed). Do NOT switch to the production host; both slots serve the same blob. Also stop on `lost contact` / `session no longer valid`. |

What the container receives and does:
- **Inputs:** the device token as an ACI secureValue. The account password never leaves the laptop.
- **Agent setup:** it writes base-url (staging), device-id and token, then runs the agent as root. PID 1 is first
  replaced by a process without the token in its environment.
- **Name:** the site name E2E2C-LNX was set at sign-in, so the container hostname does not matter.

## C2. Windows 1.2.8.1 on a throwaway VM  [SPEND about $0.23/h D2s_v4 or $0.07/h B2s, Majid's go]

| Step | Script | Touches | Check | Stop if |
|---|---|---|---|---|
| V1 | `v1-vm-create.ps1` (`-Size Standard_B2s` for the cheap one) | [SPEND] VM, disk, NIC, Standard public IP (outbound only), NSG with NO custom rule, VNet, all in folderbird-e2e-rg; vm-admin.txt on the laptop (no '-' in it: az would read a leading '-' as an option) | `vm created`; `NSG ...: 0 custom rules ... attached to the NIC`; `auto-shutdown schedules ... 0`; quota and list price lines; DONE | quota/size refusal; NSG has a rule |
| V2 | `v2-vm-provision.ps1` (+ `vm-provision.template.ps1`) | inside the VM only, as SYSTEM; also turns on Windows Search (installs the Search-Service feature if missing, WSearch Automatic + started) | `vm| zip ok`; both exes `Valid, signer Tair Foundation For CIT, timestamped`, v1.2.8.1; user fbe2e created (not admin); task FolderbirdE2ECopy; `Windows Search (WSearch): Running, Automatic` (or `... appears after the restart`); `PROVISION DONE`; `windows E2E2C-WIN` lines in hashes.txt | any `PROVISION FAILED`; `WARNING: no WSearch service` (go on, but see D2) |
| V3 | `t-device-token.ps1 -Device win` | [PROD-SHARED] Devices row E2E2C-WIN (no platform = Windows), Redis presence | `signed in E2E2C-WIN (02E2E2C00002) ... token N chars` | as C1a |
| V4 | `v4-vm-token.ps1` (+ `vm-token.template.ps1`) | inside the VM: host.txt (fbe2e + SYSTEM only), then VM restart | `vm-token.ps1 blanked`; `vm| INJECT DONE host.txt N chars, ACL ...`; `win-token.txt blanked`; DONE | `INJECT FAILED` (win-token.txt is kept: rerun V4) |
| V5 | `v5-vm-check.ps1` (+ `vm-check.ps1`), about 3 min after V4 | read-only | `vm| sessions (quser ...): fbe2e ... Active`; `FolderbirdClient pid ... owner FB-E2E2C-WIN\fbe2e ... /startup`; `Windows Search (WSearch): Running, Automatic`; `token files: host.txt present=False; host.dat present=True`; `VERDICT: app running, token migrated` | NOT READY after 4 attempts (read the wrapper / client-errors tails) |
| V6 | `v6-vm-scrub.ps1` (+ `vm-scrub.ps1`) | inside the VM: blanks leftover copies of the injection script | `vm| SCRUB DONE blanked=N failed=0`; DONE | failed > 0 (the VM is deleted in E1 anyway) |

Windows Search on a VM provisioned before this step existed: Windows Server ships with it off, and the server answers a
Windows device's search only through the Search index (no fallback), so staging-api-e2e's `search` and `mcp` steps fail
on E2E2C-WIN with HTTP 502 / isError. Run V2 again (idempotent; the app keeps running). If the VM prints
`RESTART NEEDED`, V2 restarts the VM itself (autologon and the logon task bring the app back; host.dat survives). Then
run V5 and look for the WSearch line.

Why the VM and not the laptop:
- **The risk:** anyone holding E2E_PASSWORD or E2E_API_KEY can run commands on the test device.
- **On the laptop**, that would mean Majid's az and gh sign-ins, the update-signing keys and these secret files.
- **On the VM** it means only the non-admin user fbe2e on a machine that holds nothing.
- **The token:** it only acts as this one device. fbe2e can decrypt it from host.dat anyway, so having it in the VM
  gives nothing more.

## D. Test files and dispatch inputs

**D1.** Run `d1-fixtures.ps1` after B2.
- Touches: [PROD-SHARED] Blob staging under transfers/ and commands through the shared Redis.
- What it does:
  1. Fetches test-deck.pptx and test-small.pdf at 91de08d with gh.
  2. Checks both against the SHA-256 values in tools/e2e/fixtures/README.md.
  3. Uploads both to BOTH devices with the e2e key, through `POST /api/v1/devices/{id}/files/upload`.
- **Check:**
  - four lines `<file> -> <device> <folder>: HTTP 200, delivered True, verified ...`;
  - four `fixture` lines in hashes.txt;
  - DONE.
- **Stop if:** a device is offline, or any upload answers non-200 (504 = the PC did not fetch it).

**D2.** Dispatch inputs (hashes.txt has the per-device SHA-256s; hashes are not secret).
- Dispatch ONE run at a time with `mcp__github__actions_run_trigger`, and wait for each to start. Both workflows share
  one concurrency group, and a burst cancels the runs in the middle.
- First run `staging-e2e` with action=instances and email=<e2e address> to list the instance ids A and B. With one
  staging instance, every run is same-instance.
- Staging's instance count is a separate approval and not part of this runbook.

| Input | E2E2C-WIN | E2E2C-LNX |
|---|---|---|
| staging-e2e `email` | e2e-2copy@folderbird.com (or the A1 -Email value) | same |
| `device_name` (both workflows; never the `cloudpc` default) | E2E2C-WIN | E2E2C-LNX |
| staging-e2e `folder` | default `C:\FolderbirdStaging\testfiles` | `testfiles` (relative to /root; untested walk) |
| staging-api-e2e `folder` | default | `/root/testfiles` |
| `file_name` / `expected_sha256` | `random-24mb.bin` / the `windows E2E2C-WIN random-24mb.bin` hash | `random-24mb.bin` / the `linux E2E2C-LNX random-24mb.bin` hash |
| staging-api-e2e `text_file` | `e2e-note.txt` | `e2e-note.txt` |
| staging-e2e `browser_instance` / staging-api-e2e `instance` | A, then B | A, then B |

Runs per device, each once with the pin on A and once with the pin on B:

| Workflow | action | file_name | expected_sha256 | Other |
|---|---|---|---|---|
| staging-e2e | download | default | the device's hash | |
| staging-e2e | edit | `e2e-note.txt` (it OVERWRITES that file) | blank | |
| staging-e2e | preview | `test-deck.pptx` | blank | |
| staging-e2e | preview | `test-small.pdf` | blank | add a low_disk=true run |
| staging-e2e | rename | default | | |
| staging-e2e | upload | default | | |
| staging-e2e | console | default | | |
| staging-api-e2e | | | the device's hash | steps blank (all), text_file=e2e-note.txt. For E2E2C-WIN only when V2/V5 show WSearch Running; otherwise steps=devices,browse,download,upload,exec and record that search and MCP were not covered on Windows |

- **Totals:** 16 runs per device, 32 in all, plus the one instances run.
- **Leftovers:** upload runs leave `e2e-upload-*.bin` and `e2e-api-*.bin` behind. They vanish with the devices in E1.

## P. Pointing the test PCs at PRODUCTION (Majid, 7 Nov 09:03 Riyadh: "now let's start testing the prod using the testing setup")

Production runs one copy. The test account and both test PCs stay throwaway; only the server they poll changes. No new
device token is needed for the Windows copy (one database, one token key); the Linux box is re-created, so it gets a new
one. Everything still runs from the laptop, detached, with the usual DONE / FAILED log lines.

Approval: Majid's message of 7 Nov 09:03 Riyadh ("now let's start testing the prod using the testing setup") is the
go for P2's delete and re-create of the test container and for pointing both test PCs at production. Tell Falcon
before P2 (his production watch will see the two test PCs and their downloads).

| Step | Script | What it does | Done when |
|---|---|---|---|
| P0 | `write_file` to `C:\Temp\e2e\` | copy the CURRENT `c1-linux-aci.ps1`, `aci-linux.template.yaml`, `v7-vm-target.ps1` and `vm-target.template.ps1` from this folder to the laptop (CRLF for the .ps1 files). Always copy c1 and the template together: an old c1 with the new template would create a box whose base-url is the literal placeholder | the four files on the laptop match this folder |
| P1 | `t-device-token.ps1 -Device lnx` | a fresh device token for E2E2C-LNX (signs in on staging; the token is valid on both slots) | `lnx-token.txt` saved; DONE |
| P2 | `c1-linux-aci.ps1 -Target production -Recreate` [SPEND][PROD-SHARED: the device polls production] | deletes and re-creates `fb-e2e2c-linux` (tag-checked) with base-url `https://folderbird-app.azurewebsites.net/api`, the Linux app's own default | DONE; `aci-logs.ps1` shows `[e2e] base-url: https://folderbird-app.azurewebsites.net/api` |
| P2b | `aci-logs.ps1` (2-3 min after P2) | read-only. The re-created box writes NEW random test files, so it appends NEW `linux E2E2C-LNX` lines to `hashes.txt`; use the NEWEST two (or this run's `aci| <sha>  /root/testfiles/...` lines). The older lines belong to the deleted box | `[e2e] base-url: https://folderbird-app.azurewebsites.net/api` (never `__BASEURL__`); `VERDICT: archive hash True; token file True; connected True` |
| P2c | `d1-fixtures.ps1` | [PROD-SHARED] uploads `test-deck.pptx` and `test-small.pdf` again (the old box's copies are gone; the Windows copies are re-sent with the same bytes). Needs a valid `apikey.txt`: the B2 key lives 24 h, re-run B2/B3 if it expired | the fixture lines for E2E2C-LNX; DONE |
| P3 | `v7-vm-target.ps1 -Target production` [PROD-SHARED: the test copy polls production] | rewrites `C:\FolderbirdE2E\profile-win\base-url.txt` to `https://folderbird-app.azurewebsites.net`, stops ONLY the test copy's `FolderbirdClient.exe`, waits for the logon wrapper to start it again | `vm| TARGET DONE base-url=https://folderbird-app.azurewebsites.net newpid=<n>`; DONE |
| P4 | `devices.ps1` | both test devices online (it asks staging, which reads the same database and Redis as production, so the status is the same) | E2E2C-WIN and E2E2C-LNX `online` |
| P5 | GitHub Actions | dispatch `staging-e2e.yml` and `staging-api-e2e.yml` with `target=production`, one run at a time (shared concurrency group); leave the instance-pin inputs blank (one copy). For each PC run `action=download` (or the API workflow) FIRST: console and edit can pass even from a PC that still polls staging (their replies ride the shared Redis), a download cannot | each run green; run names start with `production:` |

Inputs on production: device `E2E2C-WIN` with folder `C:\FolderbirdStaging\testfiles`; device `E2E2C-LNX` with folder
`testfiles` in the browser workflow and `/root/testfiles` in the API workflow. Files and SHA-256 are the same as in
section D for E2E2C-WIN; E2E2C-LNX has NEW random files after P2 (take their hashes from P2b). On `target=production` the browser workflow skips its Azure login and server-log step (Falcon's G8 rule:
production console lines carry real customers' file names).

Switching back: `v7-vm-target.ps1 -Target staging`, then `t-device-token.ps1 -Device lnx` and
`c1-linux-aci.ps1 -Target staging -Recreate`. Note: `v4-vm-token.ps1` refuses while the Windows copy's base-url.txt is
not the staging host, so switch it back first if it ever needs a new token. `vm-check.ps1` still probes staging's
health from the VM and its VERDICT text says "online on staging"; read that as "online" while it polls production.

## E. Cleanup (Majid's go for each step)

| Step | Script | Touches | Check | Stop if |
|---|---|---|---|---|
| E1 | `e1-delete-rg.ps1` (first, so both agents stop polling: deleting a device row does NOT sign an agent out) | [SPEND stops] deletes folderbird-e2e-rg (VM, disk, NIC, IP, NSG, VNet, container); refuses unless tagged purpose=e2e-2copy | `in the group:` list; `... is gone`; DONE | still present after 25 min (check the portal) |
| E2 | `e2-account-cleanup.ps1` (default deletes the account; `-KeepAccount` removes the devices, revokes the key and rotates the password to a value that is never stored) | [PROD-SHARED] deletes the account's Devices and ApiKeys rows and the user | `DeleteAccount -> 302 to "/"`, then `verified: a fresh sign-in with pw.txt is refused` (and `... with the bootstrap value is refused too` when bootstrap.txt still held one) and `verified: the old key gets 401` | it refuses while staging still seeds our address (A4 not done) or while the rg exists; any verification fails |
| E3 | `e3-delete-secrets.ps1` | deletes repo secrets E2E_API_KEY and E2E_PASSWORD | `neither E2E_API_KEY nor E2E_PASSWORD is listed`; DONE | still listed |
| E4 | `e4-scrub-laptop.ps1` | blanks every secret file in C:\Temp\e2e | `blanked ...` lines and the `left:` list; DONE | it refuses, blanking nothing, while old-testaccount.json holds a value (A4 not done: run A4, with -Abort if B0 never finished) |
| E5 | `p0-preflight.ps1` again | read-only | production instance ids equal step 0 (ARM); the site-wide sticky-name list equals step 0; staging ready; rg does not exist; neither E2E_* secret listed | production instance id changed (report it: amber, not caused here); sticky list changed (tell Falcon) |
| E6 | inline, gate-guarded: `Remove-Item -LiteralPath C:\Temp\e2e -Recurse -Force; 'ok'` (pass confirm_destructive only after Majid agrees) | laptop folder | `Test-Path C:\Temp\e2e` is False | |

Then post `done` in #folderbird-agents.

What stays behind on purpose:
- `mac:token:02E2E2C0000x` Redis keys, which expire after 30 days.
- NetworkWatcherRG, if Azure created it. It costs nothing; E1 logs it.
- The older e2e-staging@folderbird.com account and its devices, which this procedure never touches.

## Not verified (first run will tell)

**Windows PowerShell 5.1 on the laptop**
- None of the scripts has run under Windows PowerShell 5.1.
- .NET Framework's CookieContainer may not keep the Set-Cookie from a 302 (TempData). If not, B2 cannot read the key.
- Whether gh secret set reads stdin as expected.

**Seeder log query**
- The Log Analytics query in q-seed (`_ResourceId contains '/slots/'` is used only as a label).

**Linux container**
- That runtime-deps:8.0 can apt-get curl on ACI.
- That the staging /beta route serves the 0.2.2 blob (the hash check guards this).
- The browser walk to `testfiles` on Linux.

**Windows VM**
- How Run Command keeps or re-runs scripts across a reboot. vm-token now skips a second run with the same token.
- That autologon gives an active session with no console viewer, and that the logon task starts the tray app in it.
- Patch reboots.
- B2s with Trusted Launch.
- Whether a VM can fetch folderbird.com/download/windows (staging is the fallback).
- Azure may keep a copy of the run-command request (the token). Nothing here can blank it; E2 kills the token.

**Prices**
- The prices above are estimates; V1 logs the list price.

## Deferred hardening (needs a repo change, not done here)

The secrets are repo-level, so any workflow run on any branch of folderbird-web can read them. With the devices on
throwaway hosts, the remaining exposure is the throwaway account until E2.

To narrow it:
1. Create a GitHub Environment limited to `main`.
2. Set both secrets there with `gh secret set --env <name>`.
3. Add `environment: <name>` to the jobs in staging-e2e.yml and staging-api-e2e.yml.
4. Add an Entra federated credential for subject `repo:MajidALSarra/folderbird-web:environment:<name>`. Without it,
   staging-e2e's Log Analytics step loses its Azure login.
