# review-with-claude

Ask Claude Code for a one-shot, read-only review of local files you name, without leaving your chat. Install this plugin in Codex or Grok Build, not in Claude Code itself. It provides the `claude-review-files` skill and its PowerShell runner.

Part of [cross-agent-review](https://github.com/altstack/cross-agent-review). See the main README for all install options and details.

## What it does

When you ask, for example, "have Claude Code review plan.md", the skill tells you what will be sent, starts the Claude Code CLI once with a fixed review-only prompt, waits for the answer, and reports the verdict and every High, Mid, and Low finding. It never edits files, retries, or commits on the reviewer's say-so.

Claude gets no tools when the files are embedded in the prompt, or only `Read` when they are passed by path (plus `Glob`/`Grep` for reference folders and `WebFetch` limited to each URL's domain). Your MCP servers are not loaded.

## Data sent and where

- **Sent to Anthropic:** the files you name, plus any reference files, folders, or URLs you name, through the Claude Code CLI (`claude` on PATH), signed in with your own account. Your use is covered by Anthropic's terms and privacy policy.
- **Not sent:** anything else. The plugin has no telemetry and stores nothing unless you ask it to save the review (`-SaveOutput`). Claude Code itself may keep its own local session history, as it does for any use.
- **No secret scanning:** do not name files that contain credentials or data you may not share.

## Requirements

- Windows 10 or 11 and PowerShell 7. It runs wherever the agent you chat with loads plugins on Windows (desktop apps, editor extensions, and CLIs that support plugins); it does not run in browser-only chat apps.
- The Claude Code CLI (`claude` on PATH), installed and signed in.

## Install

Codex:

```powershell
codex plugin marketplace add altstack/cross-agent-review
codex plugin add review-with-claude@cross-agent-review
```

Grok Build:

```powershell
grok plugin install altstack/cross-agent-review#plugins/review-with-claude
```

Start a new chat session afterwards. To copy the plain skill folder instead, use `install.ps1` from the main repository.

## License

MIT