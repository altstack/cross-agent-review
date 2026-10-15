---
name: claude-review-files
description: Send one or more explicitly named local files to Claude Code for a single review-only pass, read Claude's complete answer, and report its verdict and findings. Use when the user asks Claude to review a file, plan, specification, diff file, or code (for example "have Claude review plan.md", 「このファイルをClaudeレビューして」). Do not use when you are Claude yourself, for your own review, for general opinions, or when the user asked Codex, Grok, or another model.
---

# Claude file review

Send only the files the user named to Claude Code through the bundled runner, keep supporting material separate, and return Claude's answer without mixing in your own review.

## Runner

Use the runner bundled with this skill:

```text
<this skill's directory>\scripts\invoke-claude-review.ps1
```

Requires Windows, PowerShell 7, and a signed-in Claude Code CLI (`claude`) on PATH. Do not write a replacement wrapper if the runner is missing or broken; stop and report.

## Steps

1. Resolve only the files the user explicitly named as `FilePath`, and confirm they are readable regular files. Put local files, directories, or repositories the user named as supporting material in `ReferencePath`, and explicit URLs in `ReferenceUrl`. Do not add references because they merely look related. A diff must already exist as a file; do not create one unless the user asks.
2. Before sending anything, tell the user which files will be sent to Claude and which local paths and URLs Claude may consult. A request that names the targets counts as permission for that scope. Ask first only if the targets, the intent to send them, or the presence of secrets is unclear.
3. Run the runner once with `-Transport Auto`. Put multiple files in one `-FilePath` array. Add `-Language ja` when the user is writing in Japanese; otherwise leave the default English prompt.

   ```powershell
   & 'C:\Program Files\PowerShell\7\pwsh.exe' -NoProfile -Command `
     "& '<this skill's directory>\scripts\invoke-claude-review.ps1' -FilePath @('C:\abs\one.md','C:\abs\two.ps1') -Transport Auto"
   ```

   Use `-ReviewRequest` only for a short statement of the change's purpose, scope, or non-goals that the user or the project documents actually give. For a re-review the user asked for, include the round number and the previous High findings, and ask Claude to confirm those first, to report a new High only when it is tied to the latest change and a concrete failure, and to list scope expansions separately as out-of-scope suggestions.
4. Reviews often take 5 to 20 minutes. Run the command in the background (or with a timeout of at least 30 minutes) and read its output as it arrives instead of waiting on a short command timeout. If your environment allows it, give a short progress note about once a minute. Never start a second review of the same request while one is running.
5. Check what the runner prints before Claude starts: per-file bytes, longest line, estimated tokens, and the selected transport and reason. Do not ask the user to choose Inline or Path. In Path mode Claude reads the files with Read only. References add Read for files, Read/Glob/Grep for directories, and WebFetch limited to each URL's domain.
6. If Path mode stops before starting because of a very long single line, show the file, line number, characters, and bytes, and ask the user for the original source or a formatted file. Do not switch to Inline or create a temporary copy.
7. Read Claude's whole answer. Normally report Claude's verdict, every High, Mid, and Low finding with its reason, the references Claude says it used (this is Claude's own report, not something you verified), unverified items, and the runner result. Treat only High findings as blocking and do not promote Mid or Low findings. Do not add your own review, suggestions, or fixes.
8. Show the full answer only when the user asks for it, under a heading such as `## Claude review (full text)`, keeping its Markdown and line breaks and without collapsible HTML.

## Exit codes

- `0`: Claude finished and returned an answer.
- `2`: the runner stopped before starting Claude (for example a missing file, an over-limit Inline request, or an unreadable long line), or the prompt could not be written.
- `3`: Claude reported an error result.
- `124`: no stream event for the idle limit (180 seconds by default), so the runner stopped Claude.
- Anything else is Claude's own exit code.

Confirm the reason from the runner's stderr message rather than from the number alone. On any failure, show the captured stdout, stderr, and exit code, and leave a rerun to the user. Do not log in, retry, or substitute your own or another model's review for Claude's. If Claude reports an authentication problem (such as 401), say that no Claude review was obtained and ask the user to sign in.

## Boundaries

- Use `-SaveOutput` only when the user asks to save the answer, and confirm before overwriting an existing file.
- Do not enable web access without an explicit URL.
- Do not edit files, run tests, commit, or push because of Claude's findings. Wait for a separate request.
- Never send files, URLs, credentials, internal files, or personal data beyond what the user named.
