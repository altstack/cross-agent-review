# review-with-grok

Ask xAI Grok for a one-shot, read-only review of local files you name, without leaving your chat. Install this plugin in Claude Code or Codex, not in Grok itself. It provides the `grok-review-files` skill and its PowerShell runner.

Part of [cross-agent-review](https://github.com/altstack/cross-agent-review). See the main README for all install options and details.

## What it does

When you ask, for example, "have Grok review plan.md", the skill tells you what will be sent, starts the xAI Grok CLI once with a fixed review-only prompt, waits for the answer, and reports the verdict and every High, Mid, and Low finding. It never edits files, retries, or commits on the reviewer's say-so.

Grok gets only `read_file`, `grep`, and `list_dir` (plus `web_fetch` for reference URLs) and no subagents. Grok's `--sandbox` has no effect on Windows, so the tool allowlist is what keeps it read-only.

## Data sent and where

- **Sent to xAI:** the files you name, plus any reference files, folders, or URLs you name, through the official Grok Build CLI (`%USERPROFILE%\.grok\bin\grok.exe`), signed in with your own account. Your use is covered by xAI's terms and privacy policy.
- **Not sent:** anything else. The plugin has no telemetry and stores nothing unless you ask it to save the review (`-SaveOutput`). The prompt is handed to Grok in a temporary file that is deleted when the run ends. Grok itself may keep its own local session history, as it does for any use.
- **No secret scanning:** do not name files that contain credentials or data you may not share.

## Requirements

- Windows 10 or 11 and PowerShell 7. It runs wherever the agent you chat with loads plugins on Windows (desktop apps, editor extensions, and CLIs that support plugins); it does not run in browser-only chat apps.
- The official Grok Build CLI (`%USERPROFILE%\.grok\bin\grok.exe`), installed and signed in.

## Install

Claude Code:

```powershell
claude plugin install review-with-grok --marketplace altstack/cross-agent-review
```

Codex:

```powershell
codex plugin marketplace add altstack/cross-agent-review
codex plugin add review-with-grok@cross-agent-review
```

Start a new chat session afterwards. To copy the plain skill folder instead, use `install.ps1` from the main repository.

## License

MIT