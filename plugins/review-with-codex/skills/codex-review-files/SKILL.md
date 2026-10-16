---
name: codex-review-files
description: Send one or more explicitly named local files to OpenAI Codex for a single review-only pass, read Codex's complete answer, and report its verdict and findings. Use when the user asks Codex to review a file, plan, specification, diff file, or code (for example "have Codex review plan.md", 「このファイルをCodexレビューして」). Do not use when you are Codex yourself, for your own review, for general opinions, or when the user asked Claude, Grok, or another model.
---

# Codex file review

Send only the files the user named to Codex through the bundled runner, keep supporting material separate, and return Codex's answer without mixing in your own review.

## Runner

Use the runner bundled with this skill. `<skill-dir>` below means the folder that contains this SKILL.md:

```text
<skill-dir>\scripts\invoke-codex-review.ps1
```

Requires Windows, PowerShell 7, and a signed-in Codex CLI or Codex desktop app. The runner finds Codex in this order: `-CodexPath`, the Codex CLI on PATH (including npm installs), then the Codex desktop app. Do not write a replacement wrapper if the runner is missing or broken; stop and report.

## Steps

1. Resolve only the files the user explicitly named as `FilePath`, and confirm they are readable regular files. Put local files, directories, or repositories the user named as supporting material in `ReferencePath`, and explicit URLs in `ReferenceUrl`. Do not add references because they merely look related. A diff must already exist as a file; do not create one unless the user asks.
2. Before sending anything, tell the user which files will be sent to Codex and which local paths and URLs Codex may consult. A request that names the targets counts as permission for that scope. Ask first only if the targets, the intent to send them, or the presence of secrets is unclear.
3. Run the runner once with `-Transport Auto`. Put multiple files in one `-FilePath` array. Add `-Language ja` when the user is writing in Japanese; otherwise leave the default English prompt. If the user names a model or reasoning effort for Codex (for example "use gpt-6.1-sol", 「Codexをhighで」), pass `-Model` and `-Effort` (such as `low`, `medium`, `high`, or `xhigh`); otherwise omit them so Codex uses its configured default.

   ```powershell
   & 'C:\Program Files\PowerShell\7\pwsh.exe' -NoProfile -Command `
     "& '<skill-dir>\scripts\invoke-codex-review.ps1' -FilePath @('C:\abs\one.md','C:\abs\two.ps1') -Transport Auto"
   ```

   Use `-ReviewRequest` only for a short statement of the change's purpose, scope, or non-goals that the user or the project documents actually give. For a re-review the user asked for, include the round number and the previous High findings, and ask Codex to confirm those first, to report a new High only when it is tied to the latest change and a concrete failure, and to list scope expansions separately as out-of-scope suggestions.
4. Reviews often take 5 to 20 minutes. Run the command in the background (or with a timeout of at least 30 minutes) and read its output as it arrives instead of waiting on a short command timeout. If your environment allows it, give a short progress note about once a minute. Never start a second review of the same request while one is running.
5. Check what the runner prints before Codex starts: per-file bytes, longest line, estimated tokens, the selected transport and reason, the review root, the Codex executable, and the fixed argv. Do not ask the user to choose Inline or Path.
6. Read Codex's whole answer. Normally report Codex's verdict, every High, Mid, and Low finding with its reason, the references Codex says it used (this is Codex's own report, not something you verified), unverified items, and the runner result. Treat only High findings as blocking and do not promote Mid or Low findings. Do not add your own review, suggestions, or fixes.
7. Show the full answer only when the user asks for it, under a heading such as `## Codex review (full text)`, keeping its Markdown and line breaks and without collapsible HTML.

## Exit codes

- `0`: Codex finished and returned a review.
- `2`: the runner stopped before starting Codex (for example a missing file, an over-limit Inline request, or Codex not found), or the prompt could not be written.
- `3`: Codex exited 0 but returned an empty review.
- `124`: no output for the idle limit (180 seconds by default), so the runner stopped Codex.
- Anything else is Codex's own exit code.

Confirm the reason from the runner's stderr message rather than from the number alone. On any failure, show the captured stdout, stderr, and exit code, and leave a rerun to the user. Do not log in, retry, switch binaries, or substitute your own or another model's review for Codex's. If Codex reports an authentication problem, say that no Codex review was obtained and ask the user to sign in.

## Boundaries

- Use `-SaveOutput` only when the user asks to save the answer, and confirm before overwriting an existing file.
- Do not enable web access without an explicit URL. The runner turns on live web search only for `ReferenceUrl`.
- Do not edit files, run tests, commit, or push because of Codex's findings. Wait for a separate request.
- Codex still loads its usual global and repository instructions (such as `AGENTS.md`). This skill does not block them.
- Never send files, URLs, credentials, internal files, or personal data beyond what the user named.
