---
name: grok-review-files
description: Send one or more explicitly named local files to xAI Grok (Grok Build CLI) for a single review-only pass, read Grok's complete answer, and report its verdict and findings. Use when the user asks Grok to review a file, plan, specification, diff file, or code (for example "have Grok review plan.md", 「このファイルをGrokレビューして」). Do not use when you are Grok yourself, for your own review, for general opinions, or when the user asked Claude, Codex, or another model.
---

# Grok file review

Send only the files the user named to Grok through the bundled runner, keep supporting material separate, and return Grok's answer without mixing in your own review.

## Runner

Use the runner bundled with this skill. `<skill-dir>` below means the folder that contains this SKILL.md:

```text
<skill-dir>\scripts\invoke-grok-review.ps1
```

Requires Windows, PowerShell 7, and the official Grok Build CLI installed at `%USERPROFILE%\.grok\bin\grok.exe` (or under `%GROK_HOME%`) and signed in. Browser sign-in expires after 7 days. Do not write a replacement wrapper if the runner is missing or broken; stop and report.

## Steps

1. Resolve only the files the user explicitly named as `FilePath`, and confirm they are readable regular files. Put local files, directories, or repositories the user named as supporting material in `ReferencePath`, and explicit URLs in `ReferenceUrl`. Do not add references because they merely look related. A diff must already exist as a file; do not create one unless the user asks.
2. Before sending anything, tell the user which files will be sent to Grok and which local paths and URLs Grok may consult. A request that names the targets counts as permission for that scope. Ask first only if the targets, the intent to send them, or the presence of secrets is unclear.
3. Run the runner once with `-Transport Auto`. Put multiple files in one `-FilePath` array. Add `-Language ja` when the user is writing in Japanese; otherwise leave the default English prompt. If the user names a model or reasoning effort for Grok (for example "use grok-4.6", 「Grokをlowで」), pass `-Model` and `-Effort` (such as `low`, `medium`, `high`, or `xhigh`; `grok models` lists what the account offers); otherwise omit them so Grok uses its configured default.

   ```powershell
   & 'C:\Program Files\PowerShell\7\pwsh.exe' -NoProfile -Command `
     "& '<skill-dir>\scripts\invoke-grok-review.ps1' -FilePath @('C:\abs\one.md','C:\abs\two.ps1') -Transport Auto"
   ```

   Use `-ReviewRequest` only for a short statement of the change's purpose, scope, or non-goals that the user or the project documents actually give. For a re-review the user asked for, include the round number and the previous High findings, and ask Grok to confirm those first, to report a new High only when it is tied to the latest change and a concrete failure, and to list scope expansions separately as out-of-scope suggestions.
4. Reviews often take 5 to 20 minutes. Run the command in the background (or with a timeout of at least 30 minutes) and read its output as it arrives instead of waiting on a short command timeout. If your environment allows it, give a short progress note about once a minute. Never start a second review of the same request while one is running.
5. Check what the runner prints before Grok starts: per-file bytes, longest line, estimated tokens, the selected transport and reason, the review root, the Grok executable, and the fixed argv. Do not ask the user to choose Inline or Path. Grok gets only `read_file`, `grep`, and `list_dir`, plus `web_fetch` for the listed URLs' hosts when `ReferenceUrl` is given.
6. If Path mode stops before starting because of a very long single line, show the file, line number, characters, and bytes, and ask the user for the original source or a formatted file. Do not switch to Inline or create a temporary copy.
7. Read Grok's whole answer. Normally report Grok's verdict, every High, Mid, and Low finding with its reason, the references Grok says it used (this is Grok's own report, not something you verified), unverified items, and the runner result. Treat only High findings as blocking and do not promote Mid or Low findings. Do not add your own review, suggestions, or fixes.
8. Show the full answer only when the user asks for it, under a heading such as `## Grok review (full text)`, keeping its Markdown and line breaks and without collapsible HTML.

## Exit codes

- `0`: Grok finished and returned a review.
- `2`: the runner stopped before starting Grok (for example a missing file, an over-limit Inline request, or Grok not installed).
- `3`: Grok exited 0 but returned no review text; the captured stream is shown on stderr.
- `124`: no stream event for the idle limit (180 seconds by default), so the runner stopped Grok.
- Anything else is Grok's own exit code.

Confirm the reason from the runner's stderr message rather than from the number alone. On any failure, show the captured stdout, stderr, and exit code, and leave a rerun to the user. Do not log in, set API keys, retry, or substitute your own or another model's review for Grok's. If Grok reports an authentication problem, say that no Grok review was obtained and ask the user to run `grok login`.

## Boundaries

- Use `-SaveOutput` only when the user asks to save the answer, and confirm before overwriting an existing file. The runner passes the prompt through a temporary file that it deletes when it finishes.
- Do not enable web access without an explicit URL.
- Do not edit files, run tests, commit, or push because of Grok's findings. Wait for a separate request.
- Grok's `--sandbox` has no effect on Windows; the read-only tool allowlist is what limits it. Grok still loads its usual rules and repository instructions (such as `AGENTS.md`).
- Never send files, URLs, credentials, internal files, or personal data beyond what the user named.
