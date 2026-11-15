# ChatGPT plugin: tool annotations and justifications (for the resubmission)

OpenAI rejected the plugin on 12 Nov 2026 (03:01 Riyadh, app asdk_app_6ae248707404819181bdb6a005d2bed0):
"One or more of your tool's annotations do not appear to match the tool's behavior. Please confirm annotations are
explicitly set to true or false (not null) for every tool. Include a clear justification for why the hint is set that way
based on the tool's actual behavior."

All 40 hints were already explicit booleans. The mismatch: `download_file` was labelled read-only and closed-world, but it
stores a temporary copy and returns a link anyone can open for 15 minutes without signing in. Fix: PR web-dev/mcp-annotations
(download_file -> readOnly false, destructive false, idempotent false, openWorld true). Resubmit only after that change is live.

## Final table and the text to paste into the form

| Tool | readOnly | destructive | idempotent | openWorld |
|---|---|---|---|---|
| list_devices | true | false | true | false |
| system_info | true | false | true | false |
| browse_folder | true | false | true | false |
| search_files | true | false | true | false |
| read_file | true | false | true | false |
| download_file | **false** | false | **false** | **true** |
| create_folder | false | false | true | false |
| write_file | false | true | true | false |
| upload_file | false | true | true | false |
| run_command | false | true | false | true |

### list_devices
- readOnlyHint true: It only returns the list of the user's own registered computers and whether each is online. Nothing is created, changed or deleted.
- destructiveHint false: It changes nothing anywhere.
- idempotentHint true: Calling it again with the same input has no further effect; it only reads.
- openWorldHint false: It only reads the signed-in user's own Folderbird account; it contacts nothing outside it.

### system_info
- readOnlyHint true: It runs a fixed status report on the user's own computer (OS, CPU, memory, free disk, top processes) and returns it. No file or setting is changed.
- destructiveHint false: It cannot delete or change anything.
- idempotentHint true: Repeating it only reads the current status again; it has no further effect.
- openWorldHint false: It only talks to the user's own registered computer through their account.

### browse_folder
- readOnlyHint true: It lists the names, sizes and dates in one folder on the user's computer. Nothing is changed.
- destructiveHint false: It cannot delete or change files.
- idempotentHint true: Repeating it only lists the folder again.
- openWorldHint false: It only reaches the user's own registered computer.

### search_files
- readOnlyHint true: It searches file names (or contents, if asked) on the user's computer and returns the matching paths. No file is opened for writing or changed.
- destructiveHint false: It cannot delete or change files.
- idempotentHint true: Repeating the same search has no further effect.
- openWorldHint false: It only searches the user's own registered computer.

### read_file
- readOnlyHint true: It returns the text of one file (up to 256 KB). The file is not changed.
- destructiveHint false: It cannot delete or change the file.
- idempotentHint true: Reading the same file again has no further effect.
- openWorldHint false: It only reads from the user's own registered computer and returns the text in the chat.

### download_file
- readOnlyHint false: It creates something new: a temporary copy of the file in Folderbird's storage (deleted within 2 hours) and a download link.
- destructiveHint false: It never changes or deletes anything on the user's computer or in their account; the original file is untouched.
- idempotentHint false: Every call makes a new copy and a new link, so repeating it has a further effect.
- openWorldHint true: The link it returns can be opened by anyone who has it, without signing in, for 15 minutes.

### create_folder
- readOnlyHint false: It creates a folder on the user's computer.
- destructiveHint false: It never deletes or replaces anything; if the folder already exists it says so and changes nothing.
- idempotentHint true: Creating the same folder again has no further effect.
- openWorldHint false: It only acts on the user's own registered computer.

### write_file
- readOnlyHint false: It creates or changes a text file on the user's computer.
- destructiveHint true: If a file already exists at that path it is replaced, and Folderbird keeps no copy of the old version.
- idempotentHint true: Writing the same text to the same path again leaves the same file; no further effect.
- openWorldHint false: It only acts on the user's own registered computer.

### upload_file
- readOnlyHint false: It saves a file on the user's computer.
- destructiveHint true: If a file already exists at that path it is overwritten, and no copy of the old version is kept.
- idempotentHint true: Uploading the same bytes to the same path again leaves the same file.
- openWorldHint false: It only acts on the user's own registered computer. The bytes pass through Folderbird's storage and are deleted once the computer has them.

### run_command
- readOnlyHint false: It runs a shell command on the user's computer, which can change things.
- destructiveHint true: A command can delete or change files. Folderbird refuses commands it recognises as deleting, moving, formatting or shutting down unless the user has confirmed that exact command.
- idempotentHint false: Running the same command again can have a further effect.
- openWorldHint true: A command can reach the internet and any other system the computer can reach.
