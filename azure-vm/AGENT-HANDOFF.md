# Cloud PC — Agent Handoff Notes

**Last updated:** 2026-09-12
**Maintained by:** Claude Code sessions working on this repo
**Purpose:** State of the Azure Windows cloud PC (`cloudpc`) so the next agent —
especially one operating the Windows machine through the Folderbird connector —
can pick up without re-deriving context or repeating decisions.

> **Read the "Verified vs assumed" table before acting.** Parts of this setup were
> deployed by the user outside of an agent session, so some values are inferred
> from what was handed over, not observed. Confirm anything marked *assumed*
> before you build on it.

---

## 1. What this machine is for

A personal Windows cloud PC, reachable from anywhere, intended to run
**Claude Cowork** (Electron desktop app running Claude Code sessions underneath)
plus a browser and general desktop work.

## 2. Current state

| Thing | Value | Verified? |
|---|---|---|
| Folderbird device name | `cloudpc` | **Verified** — appears in `list_devices` |
| Folderbird device id | `40` | **Verified** |
| Folderbird agent status | **Offline** as of last check | **Verified** |
| Azure resource group | `cloudpc-rg` | *Assumed* — from the deploy command handed to the user |
| Azure VM name | `cloudpc` | *Assumed* (same source) |
| Region | `eastus` | *Assumed* — user was advised to consider a closer region |
| OS | Windows 11 Pro 24H2 | *Assumed* |
| Size at creation | `Standard_B2s` (2 vCPU / 4 GB) | *Assumed* |
| Size now | Resize to `Standard_B4ms` was **recommended, not confirmed applied** | **Unknown — check** |
| Public IP | Static, Standard SKU | *Assumed* |
| Admin username | `azureuser` | *Assumed* |
| Primary access method | **Azure Bastion** (user switched to it) | **Verified** — user stated |
| Bastion SKU | Unknown — **Developer is free, Basic is ~$140/mo** | **Unknown — check** |
| Open RDP rule (3389 from `*`) | Created at deploy; deletion was advised | **Unknown — check** |

### Verify the unknowns

Run from https://shell.azure.com (Bash), or locally with `az` logged in:

```bash
# Does the RG/VM actually exist under these names?
az vm list -o table

# Power state, size, and OS
az vm show -g cloudpc-rg -n cloudpc \
  --query "{size:hardwareProfile.vmSize, os:storageProfile.imageReference.sku}" -o table
az vm get-instance-view -g cloudpc-rg -n cloudpc \
  --query "instanceView.statuses[?starts_with(code,'PowerState')].displayStatus" -o tsv

# Is RDP still open to the internet?
az network nsg list -g cloudpc-rg -o table
az network nsg rule list -g cloudpc-rg --nsg-name <nsg-name> -o table

# Which Bastion SKU is being paid for?
az network bastion list -o table
```

## 3. How to reach the machine

Four independent paths — useful to know, because they fail independently.

1. **Azure Bastion** (current primary). Browser-based RDP through the Azure
   portal, over the VM's *private* IP. Nothing exposed to the internet.
2. **Direct RDP** to the public IP (`mstsc /v:<ip>`). Works only while the open
   3389 NSG rule exists; deletion was recommended, so assume it may be gone.
3. **Folderbird** (`mcp__Folderbird__*` tools). Agent-driven shell access.
   Requires the agent process to be running on the VM — see §5.
4. **`az vm run-command`** — the reliable fallback that needs *no* agent and
   *no* open port, only Azure RBAC. Use this when Folderbird shows offline:

```bash
az vm run-command invoke -g cloudpc-rg -n cloudpc \
  --command-id RunPowerShellScript \
  --scripts 'Get-Process | Where-Object { $_.Name -like "*folderbird*" } | Select-Object Name, Id'
```

## 4. Credentials

**No credentials are stored in this repository, and none should be added.**

- Admin username is believed to be `azureuser`.
- The initial password was generated in a chat session and shared there. It must
  be treated as exposed — it was transmitted in plaintext conversation.
- **Recommended:** rotate it. From Cloud Shell:

```bash
az vm user update -g cloudpc-rg -n cloudpc -u azureuser -p '<new-strong-password>'
```

If you are an agent and you need the password, ask the user. Do not write it
into a file, a commit, an issue, or a PR.

## 5. Folderbird agent: run-at-boot decision

**Decision: the agent should run at boot on this VM (service, or a Scheduled Task
set to "Run whether user is logged on or not"). Not yet confirmed as configured.**

Rationale, so it isn't re-litigated:

- Login-only (tray app) is a sensible default on a *personal laptop* — the agent
  is only reachable while someone is actually using the machine.
- On a *cloud PC* it defeats the purpose: the machine is only manageable during
  the exact window you're already sitting at it. It also removes the recovery
  path if RDP/Bastion access ever breaks.
- Accepted cost: standing remote-execution access tied to the Folderbird account
  (outbound connection only — it opens no inbound port). Mitigation is a strong
  unique password plus 2FA on the Folderbird account.

To determine which mode is currently in place:

```powershell
Get-Service | Where-Object { $_.Name -like "*folderbird*" -or $_.DisplayName -like "*folderbird*" }
Get-ScheduledTask | Where-Object { $_.TaskName -like "*folderbird*" }
```

A **service or scheduled task** survives sign-out. A **process with neither**
dies when the RDP/Bastion session ends — which is the most likely explanation
for the device showing offline while the VM itself is running.

## 6. Sizing decision (for Claude Cowork)

| Size | vCPU / RAM | ~Cost if on 24/7 | Verdict |
|---|---|---|---|
| `Standard_B2s` | 2 / 4 GB | ~$35–45 | Deploy default. Too small for Cowork. |
| `Standard_B2ms` | 2 / 8 GB | ~$60 | Minimum. Sluggish when Cowork works while you browse. |
| `Standard_B4ms` | 4 / 16 GB | ~$120 | **Recommended.** vCPU count matters as much as RAM here. |

Resize procedure (IP is static, so it survives):

```bash
az vm deallocate -g cloudpc-rg -n cloudpc
az vm resize    -g cloudpc-rg -n cloudpc --size Standard_B4ms
az vm start     -g cloudpc-rg -n cloudpc
```

## 7. Public IP vs Bastion — why the IP was kept

Since Bastion connects over the private IP, the public IP is **not needed for
access**. It was nonetheless kept, because:

- Azure retired free default outbound access for VMs in newly created VNets. The
  attached public IP is what gives this VM its **outbound internet** (Windows
  Update, browsing, Cowork, the Folderbird agent's own connection).
- Removing it without a replacement likely leaves the VM with no internet.
- The replacement, a NAT Gateway, costs ~$32/mo versus ~$3.50/mo for the IP.

**Conclusion: keep the public IP, close the inbound RDP rule.** That yields
Bastion access from anywhere, working outbound internet, and zero exposed ports.

```bash
az network nsg rule delete -g cloudpc-rg --nsg-name <nsg-name> -n <rdp-rule-name>
```

## 8. Open items

- [ ] Confirm whether the VM was resized to `Standard_B4ms` (or at least `B2ms`).
- [ ] Confirm the Bastion SKU is **Developer** (free), not Basic (~$140/mo).
- [ ] Delete the open inbound 3389 NSG rule now that Bastion is in use.
- [ ] Configure the Folderbird agent to run at boot; confirm device shows online
      after a full sign-out.
- [ ] Install Claude Cowork on the VM (not yet done).
- [ ] Rotate the admin password (it was exposed in chat).
- [ ] Consider a closer Azure region if the desktop feels laggy over Bastion.

## 9. Cost control

```bash
az vm deallocate -g cloudpc-rg -n cloudpc   # stop compute billing (~$10/mo for disk + IP)
az vm start      -g cloudpc-rg -n cloudpc   # resume; public IP is static and persists
az group delete  --name cloudpc-rg --yes    # tear everything down
```

Note: **deallocating takes the Folderbird agent offline too.** An offline device
usually means a stopped VM, not a broken agent — check power state first (§3).

## 10. Conventions for agents working on this machine

- **Verify before you trust.** Values in §2 marked *assumed* have never been
  observed by an agent. Check, then correct this file.
- **Never commit secrets** — no passwords, no IP-plus-credential pairs, no
  connection strings. This file is pushed to GitHub.
- **Prefer `az vm run-command`** over asking the user to RDP in, when a task can
  be scripted. It works with the agent offline and no ports open.
- **Folderbird calls take 20–60s** per round trip. That latency is normal; don't
  treat it as a hang or retry-storm it.
- **Update this file** when you change the machine's state, and keep §2 and §8
  accurate — that's the part the next agent reads first.

---

## Related files

- `azure-vm/main.bicep` — the infrastructure template (VM, VNet, NSG, static IP)
- `azure-vm/deploy.sh` — one-command deploy wrapper around the template
- `azure-vm/README.md` — user-facing setup and connection instructions

**Important:** the Bicep template still reflects the *original* design — RDP open
to `*`, size `Standard_B2s`. It has **not** been updated to match the Bastion
setup or any resize. Re-deploying it as-is would reopen port 3389. Treat it as a
starting point, not a description of the live machine.
