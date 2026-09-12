# Azure Cloud PC (RDP from anywhere)

Creates a Windows VM in Azure with a **static public IP** and **RDP (port 3389)
open to the internet**, so you can connect from any device, anywhere.

> **Working on the live machine?** See [`AGENT-HANDOFF.md`](AGENT-HANDOFF.md) for
> the current state of the deployed cloud PC, access methods, decisions already
> made, and open items. The live machine has since moved to Azure Bastion and no
> longer matches this template exactly.

## What gets created

| Resource | Details |
|---|---|
| VM | `Standard_B2s` — 2 vCPU / 4 GB RAM (minimum for a usable Windows desktop) |
| OS | Windows 11 Pro (default) or Windows Server 2022 |
| Disk | 127 GB Standard SSD (marketplace Windows image minimum size) |
| Public IP | Static — stays the same across reboots |
| Network | VNet + NSG allowing inbound RDP from any IP |

## Deploy (one command)

1. Install the [Azure CLI](https://aka.ms/azure-cli) and log in:
   ```bash
   az login
   ```
2. Run the script:
   ```bash
   cd azure-vm
   ./deploy.sh
   ```
   It prompts you to choose the Windows admin password, deploys everything
   (~5 minutes), and prints the public IP and connection instructions.

### Options

Set environment variables to customize:

```bash
LOCATION=westeurope VM_SIZE=Standard_B2s OS_TYPE=win11 ./deploy.sh
```

- `LOCATION` — pick a region close to you for a responsive desktop
  (`eastus`, `westeurope`, `uaenorth`, `centralindia`, ...)
- `VM_SIZE` — `Standard_B2s` is the practical minimum. Don't go smaller for a
  desktop; 1 GB machines (`B1s`) cannot run Windows usably. `Standard_B2ms`
  (8 GB) is noticeably smoother if you browse with many tabs.
- `OS_TYPE` — `win11` (Windows 11 Pro, real PC feel) or `server2022`
  (Windows Server with desktop; no client-licensing requirement)

> **Windows 11 licensing note:** running Windows 11 in Azure uses the
> `Windows_Client` license type, which assumes you have eligible Windows
> licensing (e.g. Windows 10/11 with Multitenant Hosting Rights). If unsure,
> use `OS_TYPE=server2022`, which is fully pay-as-you-go.

## Connect

- **Windows:** press Win+R → `mstsc` → enter the public IP
- **Mac / iPhone / iPad:** install **Windows App** (App Store) → Add PC → the public IP
- **Android:** install **Microsoft Remote Desktop** (Play Store)
- **Linux:** `xfreerdp /v:<ip> /u:azureuser` or Remmina

Log in with the username (`azureuser` by default) and the password you chose.

## Cost tips

A `B2s` with Standard SSD runs roughly **$35–45/month** if left on 24/7
(varies by region). To only pay for what you use:

```bash
# stop paying for compute (keeps disk + IP, ~$10/month)
az vm deallocate -g cloudpc-rg -n cloudpc

# start it again when you need it
az vm start -g cloudpc-rg -n cloudpc
```

Delete everything when done:

```bash
az group delete --name cloudpc-rg --yes
```

## Security notes (worth 30 seconds)

RDP open to the whole internet gets password-guessing attempts within hours —
that's normal background noise, but it means:

- **Use a long, unique password** (the script enforces Azure's minimum, but
  longer is better — 16+ random characters).
- Network Level Authentication is on by default on these images; leave it on.
- If you ever want to cut the noise without losing "access from anywhere",
  the free option is Azure Bastion Developer or changing the NSG rule to your
  current IP when traveling — but as requested, this template ships fully open.
