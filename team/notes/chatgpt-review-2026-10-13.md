# ChatGPT plugin rejection and reviewer demo PC (2026-10-13)

OpenAI rejected Folderbird (v1.0.0), asdk_app_6aa3f73661c48191973dae6a4b23e6e3, on 2026-10-12 23:25 UTC: "We're unable to complete your sign-in or OAuth flow. Please ensure valid, working credentials are included and that they include no additional setup or verification to access your service."

Majid (Slack, 2026-10-13 08:34 UTC+3): "there was a session who can create VMs and Folderbird accounts, let it create a dummy low cost vm with generic files and reports and real images with test user, my ChatGPT got rejected because there're no credentials, find related sessions, give them names and call them to this chat to solve this"

Compiled by the coordinator from 9 past sessions' transcripts. No passwords or keys appear here; only where they live.

## Correction (Kestrel, 2026-10-13 06:00 UTC, from production logs)

- OpenIddict codes, access and refresh tokens are protected by Data Protection, the same key ring now held in Redis and PostgreSQL. A restart does not break them. The ephemeral keys only sign id_tokens, which the connector does not use; making them permanent is a later clean-up, not the cause.
- Production did not restart between 12 Oct 03:17 and 13 Oct 05:10 UTC. At 23:16 UTC on 12 Oct the reviewer's browser reached /connect/authorize, was sent to /Account/Login and never submitted a sign-in (no POST). The rejection came 9 minutes later: the cause is no working credentials.
- Majid's phone sign-out on 13 Oct was not caused by the key-ring rollout: his phone browser had no saved sign-in at 04:46 UTC, before the update.

## Recommendation

Start the VM work in a fresh session. Do not revive one for it. None of the 9 sessions ever created a VM, container or Folderbird account. Every Azure path that worked went through az on Majid's laptop.
- session_012AH3c7U6eHJStZEqi8W4NM (Linux container sign-in): a bridge session, unreachable since 2026-09-11. Its useful knowledge, the ACI exec recipe, is already in the laptop memory note project_linux_agent.md. A fresh local session in the same project folder loads that note automatically.
- session_015aomfeJLbbB2JGLQhib2PU and session_019Anr66zYr6ttnmgE9M2qj7: no Azure credentials, and their context is stale or nearly full.
- session_01HG215mCesDdhoybh8VhVZV, session_015bZMnmLer6YcSxZGYZJnwH, session_01XCTXmeVNtitPegcUAwoG9A: unrelated to this task.
- session_01Phc9yMB8dyr81RdyaoTxBK and session_015DG8WQeRezJymfamFHfitR: cloud sessions with no az, no browser, and folderbird.com blocked. Use them only as sources of facts (send_message); do not give them work.

Recommended: a fresh local Claude Code session on LAPTOP-MOGV95CM, titled 'infra: reviewer demo VM', in the folderbird-web worktree folder. It inherits the az login (majjod@hotmail.com, subscription 2575069a-2e8f-4cb4-98c4-fc7d2f03ab7e), Chrome and the memory note. If the laptop stays offline, there are two fallbacks:
- A fresh cloud session writes a Bicep file plus a script. Start from testportal branch claude/azure-vm-rdp-setup-xog751 (6886cdb, azure-vm/main.bicep) and remove its open 3389 rule. Majid runs it in shell.azure.com.
- The cloud session uses GitHub run_workflow on main. The deploy OIDC identity works only from refs/heads/main, and it is not known whether it has rights to create VMs.

Kickoff brief for the fresh session:
- Use a new resource group, for example folderbird-review-rg. Do not reuse cloudpc or fb-build.
- No inbound ports; use Bastion Developer (free) for admin. No auto-shutdown. Add a budget alert.
- Install the Folderbird app version that has the 45 s stall fixed. Ask Swift whether 1.2.8.1 is out.
- Windows needs auto-logon, because the tray app is not a service.
- Seed it with generic fictional reports (pdf, docx, xlsx, pptx) under names that match the test cases ('report', Annual-Report-2026.pdf, Q3-Sales-Report.xlsx) and license-free real photos with EXIF stripped.
- Sign it into the reviewer account, then check from the website that the device shows Connected.

If the OAuth cause turns out to need a code change (for example persisting OpenIddict keys), it belongs to Falcon (ops, session_014itwz7wSqp2vgLL3ZYHMxZ), Heron or a fresh web-dev session, not to the release agent.

## Facts

- Rejection on 2026-10-12 23:25 UTC: 'unable to complete your sign-in or OAuth flow ... no additional setup or verification'. None of the 9 sessions pressed Submit; who submitted, and what went into the password field, is unknown. On 2026-09-11 15:00 UTC the portal's password line still held the literal placeholder <<TYPE THE TESTER PASSWORD HERE BEFORE SUBMITTING>>. The packs also planned to send the password as a 1Password secure link, which a reviewer could count as extra setup.
- Test-credentials block as drafted: login URL https://folderbird.com/Account/Login, user tester@folderbird.com. Steps: no 2FA, SMS or email confirmation; a consent page lists six permissions; cloudpc and the Linux box are online; each tool call takes 20-60 s. Five positive test cases (list_devices; system_info; browse_folder+read_file; search 'report' plus download_file; create_folder/write_file/upload_file/run_command hostname) and three negative. The repo packs docs/submissions/chatgpt-app.md and claude-connector.md still say device HOME-DESKTOP and search 'invoice'. Runbook artifact 477a6b00 v3 says cloudpc and 'report'. Still missing on 09-11: the demo .mp4 and the policy confirmations.
- tester@folderbird.com was seeded on 2026-09-01 by Services/TestAccountSeeder.cs through create-test-account.yml run #1 (TestAccount__* settings). EmailConfirmed=true, no email sent. 2FA must stay off. It is also the Google Play reviewer account (Play Console 'Sign in details'). The seeder never changes an existing account's password. Its plan was full on 2026-09-11 (2 of 2 slots: cloudpc and SandboxHost-639240645044778914). Its existing OAuth grants (ChatGPT dev mode, the OpenAI portal scan) can be revoked under Manage > API keys.
- Since 37ec708 (prod 2026-09-17), login refuses an unconfirmed email before checking the password (AccountController.cs:75). 2FA is optional, and registration needs reCAPTCHA plus email confirmation. So the reviewer account must be seeded, never self-registered.
- Where the tester password lives: the App Service setting TestAccount__Password on both slots of folderbird-app (folderbird-rg), the inputs of create-test-account.yml run #1 (private repo MajidALSarra/folderbird-web), and Play Console. Other app secrets are in Key Vault folderbird-kv. It was exposed in chat on 2026-09-08, and on 2026-09-11 in the 018Ddfd transcript (compaction summary). An audit note recommended removing the TestAccount__* settings after review, so check that they and the account still exist.
- OAuth setup: /mcp with dynamic client registration and PKCE; consent page /connect/authorize (Views/Connect/Authorize.cshtml); scopes openid offline_access devices:read browse download upload exec. Lifetimes: access token 1 h, refresh 14 d, code 5 min. OpenIddict uses UseDataProtection with its key ring in Redis (folderbird:dataprotection-keys) and ephemeral signing and encryption keys. The 2026-10-11 Redis wipe, and any restart or second instance, invalidates codes and tokens. No audience check on /mcp. connector-smoke.yml walks the full flow as tester and passed 42/42 on 2026-09-09. Rerun it on prod after the 2026-10-13 05:23 key-ring change; it is the fastest first test.
- cloudpc: Azure VM in CLOUDPC-RG, Standard_B2ms (Windows 11 Pro from the 08-10 template, eastus assumed). Built by Majid as his personal cloud PC. Tester device 43 since 09-05, but a cloudpc device 40 on Majid's account was online on 09-16 with his personal folders (Claude, DGA, Projects, OneDrive). Folderbird 1.2.7.0 there returns results after about 62 s against a 45 s MCP limit. The admin password was exposed in chat on 08-10. RDP 3389 may still be open to any address. Its state after the 10-11 suspension is unknown.
- folderbird-linux-demo: ACI in folderbird-rg, westeurope, 1 vCPU / 1.5 GB, roughly $30-35 a month (estimate), Linux agent 0.2.1. The sign-in token lives on the container's own disk, so any restart, likely including the 10-11 suspension, sends it back to WAITING FOR SIGN-IN. The Linux build turns '/' into '\' in write_file and upload_file, which breaks positive test case 5.
- Other compute: fb-build (folderbird-build-rg, D2s_v4, deallocated, signed into Majid's account, holds build tools and his code; do not reuse). Legacy deallocated VMs: FolderBirdServer, folderbird, Folderbird. The subscription's DSv5 quota is 0, so use B-series. The Windows tray app is not a service, so a Windows VM stays offline until someone logs on unless auto-logon is set.
- Azure access paths: (1) az on LAPTOP-MOGV95CM (Folderbird device 39), through a local or bridge session or through Folderbird run_command (capped at 45 s per command); (2) Azure Cloud Shell, run by Majid; (3) the GitHub deploy OIDC identity, only from main (branches fail with AADSTS700213). Cloud containers have no az. Templates: testportal azure-vm/main.bicep (branch claude/azure-vm-rdp-setup-xog751) and folderbird-web tools/azure/new-build-vm.ps1.
- OpenAI domain challenge: route /.well-known/openai-apps-challenge, token in setting OpenAi__AppsChallengeToken. The reports disagree on whether it is slot-sticky; check before any swap. The Claude directory needs a Team or Enterprise org, so it was never submitted.
- Team rules: production changes, spending and deletions wait for Majid's go, typed in the channel or in the agent's own chat. Falcon (ops, session_014itwz7wSqp2vgLL3ZYHMxZ) owns production and the Azure account. Heron owns multi-instance scale-out. Ask them before touching App Service settings, the Redis key ring or billing.

## Risks

- 2FA and lockout: before resubmitting, check that the reviewer account has TwoFactorEnabled=false, EmailConfirmed=true and no LockoutEnd. Reviewers trying a placeholder or old password may have locked it.
- OAuth fragility: ephemeral signing and encryption keys plus a Redis-held key ring mean a restart, a second instance or a Redis flush during review can break sign-in again. Persist the keys durably and re-run connector-smoke on prod before resubmitting. Coordinate with Falcon and Heron.
- Shared account: rotating the tester password breaks the Google Play reviewer login unless Play Console is updated too. The plan is also full (2/2), so a new VM cannot join without freeing a slot. A separate OpenAI reviewer account avoids both.
- Real-data exposure: the exec scope gives reviewers a shell on the device. cloudpc held Majid's personal data, so do not use it. The demo VM must hold no az or gh login, no keys, no managed identity with rights and no Majid account. Images must be license-free with EXIF and GPS stripped. Use a separate resource group and no inbound ports (do not repeat cloudpc's 3389-to-any rule).
- Abuse and cost: shell access can be misused (mining, outbound abuse). Keep the VM small and add a budget alert. Azure was just suspended for an unpaid bill, so any new spend needs Majid's go. Rough monthly costs: Linux B1s/B1ms about $10-20; Windows B2s about $35-45 plus about $3.65 for a public IP. Do not add auto-shutdown during review. cloudpc, the ACI and fb-build's disk and IP keep billing until Majid decides on them.
- Device readiness: Windows 1.2.7.0 stalls past the 45 s MCP limit; Linux 0.2.1 breaks write_file and upload_file paths; a Windows box needs auto-logon; ACI tokens vanish on restart. Any of these can fail review even with a working OAuth flow.
- Credentials: the password goes only into the OpenAI form's test-credentials field, typed by Majid or with his explicit approval in his own chat. Never post it in Slack (#folderbird-agents or Pigeon), the team room, send_message, commits, CLAUDE.md or artifacts, and do not use an external secure link. It was already exposed twice, so rotate it first.
- The revived bridge session depends on the laptop being online, and the auto-mode classifier may block az or portal steps until Majid approves them in that session's chat.

## Open questions for Majid

- Who pressed Submit, and what went into the OpenAI password field: the placeholder, a 1Password link or the real password? Has the tester password changed since then? Did the rejection come with any detail or screenshot?
- Reuse tester@folderbird.com (shared with Google Play, plan 2/2 full) or seed a separate account, for example openai-review@folderbird.com, with its own device slot? OK to rotate the password?
- Go to spend on a new reviewer VM? Windows B2s (about $35-45 a month, matches the 'cloudpc' screenshots) or Linux B1ms (about $15 a month, but it has the write_file path bug)? For how long, and with what budget cap?
- Keep, deallocate or delete cloudpc and folderbird-linux-demo? Was cloudpc's personal data fully removed, or is it back on your account as device 40?
- Can you keep LAPTOP-MOGV95CM online so the revived release session and a fresh infra session can use az and Chrome? If not, will you run a script in Azure Cloud Shell?
- Go to deploy an OAuth key-persistence fix to production if that is the cause (Falcon's area)?
- Which images are acceptable as 'real images' (stock or public-domain, or your own non-personal photos)? Who records the required demo .mp4?

## Sessions read

- `session_012AH3c7U6eHJStZEqi8W4NM` Sign the Linux demo container into the tester account: fit partial. Fits the task:
- The session has a working Azure CLI on Majid's laptop, signed in as majjod@hotmail.com on "Azure subscription 1" (id 2575069a-2e8f-4cb4-98c4-fc7d2f03ab7e). It has Claude in Chrome on the same laptop and has already set up a reviewer device under tester@folderbird.com.
- It knows the ACI demo well, including the exec recipe.

Does not fit:
- It never created a VM, container or Fold
- `session_01Phc9yMB8dyr81RdyaoTxBK` Submit Folderbird as a Claude connector and a ChatGPT app: fit partial. It holds the most detailed context on the submission packs, the reviewer test account (tester@folderbird.com), the cloudpc demo box and the OAuth/consent code. But it cannot do the new task:
- No Azure CLI or VM tooling; it never created a VM.
- Its egress proxy blocked folderbird.com, the OpenAI and Claude docs, and most other sites.
- No browser.
- It cannot message other sessions.
- It has been
- `session_018Ddfd56Kg2AsHaVs7na6cz` Enter the Folderbird ad pack into Google Ads (also did the ChatGPT portal draft): fit partial. Partial fit. It knows the reviewer setup in detail: tester@folderbird.com, cloudpc, the Linux demo container, the demo files, the OpenAI draft and the cloudpc result stall. It also had Azure CLI and Chrome on Majid's laptop. But it did not create any VM, container or Folderbird account; they all came from earlier sessions. It refuses to type or handle passwords. The auto-mode classifier blocked ev
- `session_015aomfeJLbbB2JGLQhib2PU` Azure VM with RDP access: fit partial. The session never had Azure credentials, so it could not create VMs, and it never created or used any Folderbird account. That rules it out as the session "who can create VMs and Folderbird accounts". What is worth reusing is on the branch and does not need this session. claude/azure-vm-rdp-setup-xog751 (now at 6886cdb, not merged into the current checkout) holds a working low-cost Windows VM temp
- `session_019Anr66zYr6ttnmgE9M2qj7` Folderbird Windows build VM setup: fit partial. It knows how to do Azure work with no Azure credentials in the cloud: run az on Majid's laptop (device 39) through Folderbird run_command, or run run-command on the VM as SYSTEM. It also knows tools/azure/new-build-vm.ps1 and the bootstrap script. And it learned a fact that matters for a reviewer box: the Folderbird tray app is not a service, so a started VM stays OFFLINE in Folderbird until someo
- `session_01HG215mCesDdhoybh8VhVZV` Cloud PC setup in Google Cloud: fit none. This session never created a VM, container or Folderbird account. It had no working cloud credentials and never touched Folderbird, OAuth, ChatGPT or Claude submissions. Its only output is research on Riyadh cloud regions (OCI me-riyadh-1 Windows Server pricing, Cowork OS limits). That research is loosely useful for picking a cheap Windows VM, but the session has nothing to build on for a reviewer
- `session_015bZMnmLer6YcSxZGYZJnwH` Azure application setup: fit none. The session is unrelated to the ChatGPT OAuth rejection or to building a reviewer VM or test account. It answered one general question about Azure LLM pricing and AI services in August 2026 and never touched Azure resources, VMs, Folderbird accounts, OAuth or app submissions. Its context is a 401k-token claude-api skill dump plus a pricing answer, so there is nothing to build on. A fresh session, 
- `session_01XCTXmeVNtitPegcUAwoG9A` Admin page unconfirmed emails: fit none. This was a narrow admin-UI change to folderbird-web and has nothing to do with the reviewer-login task. It created no VMs or containers and ran no az, gcloud or docker commands. It created no Folderbird accounts and had no test or demo users or data. It did no 2FA or email-confirmation setup for any account and never touched the ChatGPT or Claude submissions. It created no Key Vault and handled no
- `session_015DG8WQeRezJymfamFHfitR` Folderbird registration issue: fit partial. Partly useful: it knows the sign-up, login, email-confirmation and 2FA code well (the area behind "credentials must need no extra setup or verification"). It also showed it can dispatch folderbird-web GitHub workflows on main from an interactive session, which is how create-test-account.yml makes a pre-verified reviewer account. It cannot create VMs: it had no Azure CLI, az is not installed on clo
