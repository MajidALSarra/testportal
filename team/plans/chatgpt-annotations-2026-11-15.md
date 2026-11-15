# ChatGPT plugin: tool annotations and justifications (for the resubmission)

OpenAI rejected the plugin on 12 Nov 2026 (03:01 Riyadh, app asdk_app_6ae248707404819181bdb6a005d2bed0):
"One or more of your tool's annotations do not appear to match the tool's behavior. Please confirm annotations are
explicitly set to true or false (not null) for every tool. Include a clear justification for why the hint is set that way
based on the tool's actual behavior."

The email names no tool. All 40 hints were already explicit booleans, so the problem was the values. Two causes found
(review of 15 Nov, plus Falcon):
1. `download_file` was labelled read-only and closed-world, but each call makes a temporary transfer copy and returns a
   link anyone can open for 15 minutes without signing in.
2. `write_file`, `upload_file` and `create_folder` were openWorld false. OpenAI's Apps SDK guidance says to leave
   openWorldHint true "for tools that can write to arbitrary URLs/files/resources", and these accept any path the
   computer can open (network shares, mapped drives, cloud-synced folders).
3. (Wren, 15 Nov 13:02 UTC, from OpenAI's live plugin guidance) openWorld is about reaching external systems whether a
   tool reads or writes; OpenAI's own example is public web search, read-only AND open-world. browse_folder,
   search_files and read_file accept any path too, so they reach the same places: openWorld true. Only list_devices
   and system_info take no path and stay closed. openWorld does not by itself make ChatGPT ask before a call.
Fix: PR #111 (web-dev/mcp-annotations) plus the follow-up for the three reads (web-dev/mcp-annotations-reads). Sources for the definitions: the MCP spec ToolAnnotations schema, and OpenAI's
Apps SDK text as quoted by third-party mirrors (developers.openai.com was not reachable from our sessions). Wren checks
OpenAI's own page before pasting.

## Resubmission steps (only after PR #111 is live on folderbird.com)

1. In the OpenAI portal, open the plugin draft and run the MCP tools scan again, so it reads the new labels. Reload the
   draft page afterwards (the portal does not refresh on its own after a scan).
2. Check that the scanned values for all 10 tools match the table below exactly. If any differ, stop and tell the
   coordinator.
3. If the form still asks for justifications (Wren: current guidelines may no longer require them), paste the ones below, one per hint.
4. Majid presses Submit for review.

## Final table and the text to paste into the form

| Tool | readOnly | destructive | idempotent | openWorld |
|---|---|---|---|---|
| list_devices | true | false | true | false |
| system_info | true | false | true | false |
| browse_folder | true | false | true | **true** |
| search_files | true | false | true | **true** |
| read_file | true | false | true | **true** |
| download_file | **false** | false | **false** | **true** |
| create_folder | false | false | true | **true** |
| write_file | false | true | true | **true** |
| upload_file | false | true | true | **true** |
| run_command | false | true | false | true |

### list_devices
- readOnlyHint true: It only returns the list of the user's own registered computers and whether each is online. Nothing is created, changed or deleted.
- destructiveHint false: It changes nothing anywhere.
- idempotentHint true: Calling it again with the same input has no further effect; it only reads.
- openWorldHint false: It takes no path or command: it only reads the signed-in user's own Folderbird device list and returns it in the chat. It reaches nothing else and sends, publishes or writes nothing.

### system_info
- readOnlyHint true: It runs a fixed status report on the user's own computer (OS, CPU, memory, free disk, top processes) and returns it. No file or setting is changed.
- destructiveHint false: It cannot delete or change anything.
- idempotentHint true: Repeating it only reads the current status again; it has no further effect.
- openWorldHint false: It takes no path or command: it runs one fixed status report on the user's own registered computer and returns it in the chat. It reaches nothing else and sends, publishes or writes nothing.

### browse_folder
- readOnlyHint true: It lists the names, sizes and dates in one folder on the user's computer. Nothing is changed.
- destructiveHint false: It cannot delete or change files.
- idempotentHint true: Repeating it only lists the folder again.
- openWorldHint true: It lists any folder the user's computer can open, including network shares, mapped drives and cloud-synced folders, so it can reach systems beyond the computer itself. It only reads; it sends, publishes or writes nothing.

### search_files
- readOnlyHint true: It searches file names (or contents, if asked) on the user's computer and returns the matching paths. No file is opened for writing or changed.
- destructiveHint false: It cannot delete or change files.
- idempotentHint true: Repeating the same search has no further effect.
- openWorldHint true: It can search any folder the user's computer can open, including network shares, mapped drives and cloud-synced folders. It only reads; it sends, publishes or writes nothing.

### read_file
- readOnlyHint true: It returns the text of one file (up to 256 KB). The file is not changed.
- destructiveHint false: It cannot delete or change the file.
- idempotentHint true: Reading the same file again has no further effect.
- openWorldHint true: It reads from any path the user's computer can open, including network shares, mapped drives and cloud-synced folders. It only reads and returns the text in the chat; it sends, publishes or writes nothing.

### download_file
- readOnlyHint false: It creates something new: a temporary transfer copy of the file in Folderbird's transfer storage (normally deleted after 2 hours, always within a day) and a new download link.
- destructiveHint false: It never changes or deletes anything on the user's computer or in their account; the original file is untouched.
- idempotentHint false: Every call makes a new copy and a new link, so repeating it has a further effect.
- openWorldHint true: The link it returns can be opened by anyone who has it, without signing in, for 15 minutes. Images up to 3.5 MB are also returned in the chat.

### create_folder
- readOnlyHint false: It creates a folder on the user's computer.
- destructiveHint false: It never deletes or replaces anything; if the folder already exists it says so and changes nothing.
- idempotentHint true: Creating the same folder again has no further effect.
- openWorldHint true: It creates a folder at any path the user's computer can open, including network shares, mapped drives and cloud-synced folders.

### write_file
- readOnlyHint false: It creates or changes a text file on the user's computer.
- destructiveHint true: If a file already exists at that path it is replaced, and Folderbird keeps no copy of the old version.
- idempotentHint true: Writing the same text to the same path again leaves the same file and nothing else behind. The text passes through Folderbird's transfer storage only on its way to the computer, is never returned or shared, and is deleted once the computer has it.
- openWorldHint true: It writes to any path the user's computer can open, including network shares, mapped drives and cloud-synced folders.

### upload_file
- readOnlyHint false: It saves a file on the user's computer.
- destructiveHint true: If a file already exists at that path it is overwritten, and no copy of the old version is kept.
- idempotentHint true: Uploading the same bytes to the same path again leaves the same file and nothing else behind. The bytes pass through Folderbird's transfer storage only on their way to the computer, are never returned or shared, and are deleted once the computer has them.
- openWorldHint true: It saves to any path the user's computer can open, including network shares, mapped drives and cloud-synced folders.

### run_command
- readOnlyHint false: It runs a shell command on the user's computer, which can change things.
- destructiveHint true: A command can delete or change files. Folderbird refuses commands it recognises as deleting, moving, formatting or shutting down unless the call sets confirm_destructive to true. The assistant is told to set it only after the user confirms the exact command; Folderbird cannot check that it did. Every refusal is recorded.
- idempotentHint false: Running the same command again can have a further effect.
- openWorldHint true: A command can reach the internet and any other system the computer can reach.
