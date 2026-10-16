# review-with-codex

Ask OpenAI Codex for a one-shot, read-only review of local files you name, without leaving your chat. Install this plugin in Claude Code or Grok Build, not in Codex itself. It provides the `codex-review-files` skill and its PowerShell runner.

Part of [cross-agent-review](https://github.com/altstack/cross-agent-review). See the main README for all install options and details.

## What it does

When you ask, for example, "have Codex review plan.md", the skill tells you what will be sent, starts the OpenAI Codex CLI once with a fixed review-only prompt, waits for the answer, and reports the verdict and every High, Mid, and Low finding. It never edits files, retries, or commits on the reviewer's say-so.

Codex runs `codex exec` in its read-only sandbox; live web search is enabled only when you pass a reference URL.

## Data sent and where

- **Sent to OpenAI:** the files you name, plus any reference files, folders, or URLs you name, through the Codex CLI (`npm install -g @openai/codex`) or the Codex desktop app, signed in with your own account. Your use is covered by OpenAI's terms and privacy policy.
- **Not sent:** anything else. The plugin has no telemetry and stores nothing unless you ask it to save the review (`-SaveOutput`). Codex itself may keep its own local session history, as it does for any use.
- **No secret scanning:** do not name files that contain credentials or data you may not share.

## Requirements

- Windows 10 or 11 and PowerShell 7. It runs wherever the agent you chat with loads plugins on Windows (desktop apps, editor extensions, and CLIs that support plugins); it does not run in browser-only chat apps.
- The Codex CLI (`npm install -g @openai/codex`) or the Codex desktop app, installed and signed in.

## Install

Claude Code:

```powershell
claude plugin install review-with-codex --marketplace altstack/cross-agent-review
```

Grok Build:

```powershell
grok plugin install altstack/cross-agent-review#plugins/review-with-codex
```

Start a new chat session afterwards. To copy the plain skill folder instead, use `install.ps1` from the main repository.

## License

MIT