# Connect Folderbird with Claude and ChatGPT

<!-- Two versions of the "Add as a connector" steps. Show NOW until the listing is approved,
     then swap in AFTER APPROVAL. Everything else stays the same.
     Facts checked 2026-10-12 against folderbird-web 2972e90 (ConnectController.cs:44-52, DeviceOps.cs:70-76 and
     :301-305, Program.cs:114-131, Views/Connect/Authorize.cshtml) and team/notes/connector-page-factcheck-2026-10-12.md.
     Claude steps from Anthropic's current docs. ChatGPT steps come from OpenAI search snippets only:
     CLICK THROUGH THEM ONCE IN A REAL CHATGPT ACCOUNT BEFORE PUBLISHING.
     ChatGPT submission received 2026-09-29 (C-HxB54ssYyJy8), no decision yet. No Anthropic directory email seen. -->

Folderbird lets Claude and ChatGPT reach the files on your own PC. You ask in plain words, and the AI finds, reads or saves files for you. Your files stay on your PC. Nothing is synced to the cloud.

## Before you start

You need:

1. A Folderbird account (free or paid). Sign up at https://folderbird.com.
2. The Folderbird app installed and signed in on at least one PC (Windows, or the Linux beta). The PC must be on.
3. A Claude or ChatGPT plan that lets you add connectors (see the notes under each).

## Connect to Claude

### NOW (custom connector)

1. Open Claude (claude.ai or Claude Desktop).
2. Go to **Customize → Connectors** (claude.ai/customize/connectors). In Claude Desktop, click **Customize** in the sidebar, then **Connectors**.
3. Click **Add custom connector**.
4. Name: `Folderbird`. URL: `https://folderbird.com/mcp`
5. Click **Continue**, keep the sign-in setting **Sign in now**, click **Continue**, then **Add**. If Folderbird shows a **Connect** button, click it.
6. Sign in to Folderbird.
7. Check the list of what Claude may do, then click **Allow**.
8. Done. Start a new chat and try a first prompt (see below).

On a Team or Enterprise plan, an Owner may need to add the connector first.

### AFTER APPROVAL (connector directory)

1. Open Claude and go to **Customize → Connectors**.
2. Click **Discover** (or **+** next to Connectors) and search for **Folderbird**.
3. Click **Connect to Claude**.
4. Sign in to Folderbird and click **Allow**.
5. Done. Start a new chat and try a first prompt.

Team and Enterprise: an Owner adds Folderbird under **Organization settings → Connectors → Browse connectors**. Members may see **Request**, which asks the Owner to add it.

## Connect to ChatGPT

### NOW (developer mode)

1. Open ChatGPT on the web.
2. Go to **Settings → Apps → Advanced settings** and turn on **Developer mode**. (On some accounts it is under **Settings → Security and login**.)
3. Click **Plugins** in the sidebar, click **+**, then **Add custom MCP server**.
4. Name: `Folderbird`. URL: `https://folderbird.com/mcp`. Authentication: **OAuth**.
5. Click **Create**. ChatGPT opens the Folderbird sign-in page. (If not, click **Connect** on the Folderbird plugin.)
6. Sign in to Folderbird and click **Allow**.
7. Done. In a new chat, type `@Folderbird` and pick it from the list.

Which plans: on ChatGPT Business, Enterprise and Edu, an admin must allow developer mode first. On Pro, ChatGPT may allow only reading files, not saving them or running commands. Free accounts are not supported.

### AFTER APPROVAL (ChatGPT plugins)

1. Open ChatGPT (web, desktop or mobile) and click **Plugins** in the sidebar.
2. Search for **Folderbird** and open it.
3. Click **Install plugin**, then **Connect**.
4. Sign in to Folderbird and click **Allow**.
5. Done. Type `@Folderbird` in a chat, or just ask.

## What you are allowing

The Allow page lists what the AI may do. Here is what each item means:

| On the Allow page | What it means |
|---|---|
| See your devices, whether they are online, and their health (system info) | List your PCs and whether they are on, plus CPU, memory and disk |
| Browse folders and search for files on your devices | List folders and search files by name or by what is inside |
| Read and download files from your devices | Read text files and make a download link for any file |
| Create folders and write or upload files to your devices | Make folders and save files. A file with the same name is replaced |
| Run commands on your devices ⚠️ | Run a command on your PC. Commands that delete, move, format or shut down are refused until you confirm them in the chat |
| Stay connected without signing in again (refresh tokens) | Claude or ChatGPT can renew access without asking you to sign in each time |

The connection covers every PC in your account. Want to limit it to some PCs or fewer permissions? Use an API key instead (see **Advanced** below).

## Try these first prompts

1. "Which of my PCs are online, and how much free disk does each have?"
2. "Find the PDF in my Documents that mentions the budget and give me a download link."
3. "What's in todo.txt on my laptop? Add 'call the bank' to the end."
4. "Make a folder called Receipts in my Documents."
5. "My PC is slow. What is using the most CPU and memory?"

Tip: each request travels to your PC and back, so an answer can take 20 to 60 seconds. That is normal.

## Safety

- **Your files stay on your PC.** Folderbird never syncs them. When you download one, a temporary copy passes through Folderbird and is deleted within 2 hours. The download link works for 15 minutes.
- **You approve first.** Nothing works until you sign in and click Allow.
- **Risky commands wait for you.** Commands that delete, move, format or shut down are refused at first. Folderbird tells the AI to show you the exact command and ask before it tries again.
- **Commands are logged.** Every command the AI runs, including refused ones, shows on your API keys page (folderbird.com/Manage/ApiKeys). Only the command name is kept, never its details.
- **Stop anytime.** Disconnect Folderbird in Claude or ChatGPT settings to end access. Access tokens last 1 hour and renew automatically. If you don't use the connection for 14 days, you'll be asked to sign in again.

## Troubleshooting

| Problem | Fix |
|---|---|
| "No devices" or "device offline" | Turn on the PC and make sure the Folderbird app is running and signed in to the same account |
| The answer takes a long time | Wait up to a minute. Each request goes to your PC and back |
| I closed the Allow page by mistake | Click Connect again, or remove the connector and add it again |
| "Access denied" | You clicked Cancel. Click Connect again and choose Allow |
| A file search finds nothing | On Windows, search uses the Windows Search index. Make sure the folder is indexed, or ask the AI to browse the folder instead |
| It stopped working after a while | Your sign-in expired. Click Connect again in the connector settings |
| I can't see "Add custom connector" or "Developer mode" | Your plan or workspace may not allow custom connectors yet. Check with your admin, or wait for the official listing |

Still stuck? Email info@folderbird.com.

## Advanced: other AI tools (API key)

Claude Desktop config files, OpenClaw and other MCP tools can connect with a Folderbird API key. Create one on your API keys page: click your name at the top right, then **API keys → Manage keys** (folderbird.com/Manage/ApiKeys). Pick only the PCs and permissions it needs. For the setup lines, see **AI & Integrations → AI Agents & MCP** (folderbird.com/Integrations/Agents). For n8n and scripts, use the REST API (API Reference).
