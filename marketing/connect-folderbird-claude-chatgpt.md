# Connect Folderbird with Claude and ChatGPT

<!-- Two versions of the "Add as a connector" step. Show NOW until the listing is approved,
     then swap in AFTER APPROVAL. Everything else stays the same.
     Facts checked 2026-10-12 against folderbird-web docs/submissions/*.md and Views/Connect/Authorize.cshtml.
     ChatGPT submission received 2026-09-29 (C-HxB54ssYyJy8), no decision yet. No Anthropic directory email seen. -->

Folderbird lets Claude and ChatGPT reach the files on your own PC. You ask in plain words, and the AI finds, reads or saves files for you. Your files stay on your PC. Nothing is synced or stored in the cloud.

## Before you start

You need:

1. A Folderbird account (free or paid). Sign up at https://folderbird.com.
2. The Folderbird app installed and signed in on at least one PC (Windows, or the Linux beta). The PC must be on.
3. A Claude or ChatGPT account that can add connectors.

## Connect to Claude

### NOW (custom connector)

1. Open Claude (claude.ai or Claude Desktop).
2. Go to **Settings → Connectors**.
3. Click **Add custom connector**.
4. Name: `Folderbird`. URL: `https://folderbird.com/mcp`
5. Click **Add**, then **Connect**.
6. Sign in to Folderbird.
7. Check the list of what Claude may do, then click **Allow**.
8. Done. Start a new chat and try a first prompt (see below).

### AFTER APPROVAL (connector directory)

1. Open Claude and go to **Settings → Connectors**.
2. Click **Browse connectors** and search for **Folderbird**.
3. Click **Connect**.
4. Sign in to Folderbird and click **Allow**.
5. Done. Start a new chat and try a first prompt.

## Connect to ChatGPT

### NOW (developer mode)

1. Open ChatGPT on the web.
2. Go to **Settings → Apps & connectors → Advanced** and turn on **Developer mode**.
3. Back in **Apps & connectors**, click **Create**.
4. Name: `Folderbird`. URL: `https://folderbird.com/mcp`. Authentication: **OAuth**.
5. Click **Create**, then **Connect**.
6. Sign in to Folderbird and click **Allow**.
7. Done. In a new chat, pick Folderbird from the tools menu and try a first prompt.

### AFTER APPROVAL (ChatGPT apps)

1. Open ChatGPT and go to **Settings → Apps & connectors** (or the apps list).
2. Search for **Folderbird**.
3. Click **Connect**.
4. Sign in to Folderbird and click **Allow**.
5. Done. Type `@Folderbird` in a chat, or just ask.

## What you are allowing

The Allow page lists exactly what the AI can do:

| Permission | What it means |
|---|---|
| See your devices | List your PCs and whether they are online, plus CPU, memory and disk |
| Browse | List folders and search files by name or by what is inside |
| Download | Read text files and make a download link for any file |
| Upload | Create folders, save files, and change text files (a file with the same name is replaced) |
| Run commands ⚠️ | Run a command on your PC. Anything that deletes, moves, formats or shuts down is blocked until you say yes in the chat |

The connection covers every PC in your account. Want to limit it to some PCs or fewer permissions? Use an API key instead (see **Advanced** below).

## Try these first prompts

1. "Which of my PCs are online, and how much free disk does each have?"
2. "Find the PDF in my Documents that mentions the budget and give me a download link."
3. "What's in todo.txt on my laptop? Add 'call the bank' to the end."
4. "Make a folder called Receipts in my Documents."
5. "My PC is slow. What is using the most CPU and memory?"

Tip: each request travels to your PC and back, so an answer can take 20 to 60 seconds. That is normal.

## Safety

- **Your files stay on your PC.** Folderbird never syncs or stores them. A download only passes through Folderbird, and the link expires after 15 minutes.
- **You approve first.** Nothing works until you sign in and click Allow.
- **Risky commands wait for you.** Delete, move, format and shut down are refused until you confirm the exact command in the chat.
- **Everything is logged.** Every command and file action shows on your **API keys** page in Folderbird.
- **Stop anytime.** Disconnect Folderbird in Claude or ChatGPT settings and access ends right away. Access tokens last 1 hour and renew for up to 14 days only while you use them.

## Troubleshooting

| Problem | Fix |
|---|---|
| "No devices" or "device offline" | Turn on the PC and make sure the Folderbird app is running and signed in to the same account |
| The answer takes a long time | Wait up to a minute. Each request goes to your PC and back |
| I closed the Allow page by mistake | Remove the connector and add it again, or click Connect again |
| "Access denied" | You clicked Cancel. Click Connect again and choose Allow |
| A file search finds nothing | On Windows, search uses the Windows Search index. Make sure the folder is indexed, or ask the AI to browse the folder instead |
| It stopped working after a while | Your sign-in expired. Click Connect again in the connector settings |
| I can't see "Add custom connector" or "Developer mode" | Your plan or workspace may not allow custom connectors yet. Check with your admin, or wait for the official listing |

Still stuck? Email info@folderbird.com.

## Advanced: other AI tools (API key)

Claude Desktop config files, Cursor, n8n, OpenClaw and other MCP tools can connect with a Folderbird API key. Create one on **Manage → API keys**, pick only the PCs and permissions it needs, and see **Integrations → AI Agents & MCP** for the setup lines.
