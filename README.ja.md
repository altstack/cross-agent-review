# cross-agent-review

[English](README.md)

チャットを離れずに、別のコーディングエージェントへセカンドオピニオンを頼むためのスキル集です。Claude Code、Codex、Grok Buildのどれかとの会話で「plan.mdをCodexにレビューさせて」（ClaudeやGrokも同様）と頼むと、指定したファイルだけを相手のCLIへ1回だけレビュー限定で送り、回答全文を持ち帰ります。

- **どの方向でも**：Claude Code・OpenAI Codex・xAI Grok Buildの間の6方向すべてに対応します
- **今のログインのまま**：各CLIで普段使っているサインインを使います。APIキーは不要です
- **レビュー役は読むだけ**：レビュー役には読み取り用の機能だけ（Codexは読み取り専用の隔離モード）を渡し、編集しないよう指示します
- **Gitの差分に限らない**：計画書・仕様書・文書・コードを名指しでレビューできます。参考資料（ファイル・フォルダー・URL）はレビュー対象と分けて渡せます
- **Windowsでそのまま動く**：PowerShell 7だけで動き、WSLは不要です

Claude CodeからCodexへGitの変更だけをレビューさせたいなら、OpenAI公式の[codex-plugin-cc](https://github.com/openai/codex-plugin-cc)（`/codex:review`）が適しています。このプロジェクトは、ファイルの名指し、それ以外の方向、Grok、Windowsでの利用を対象にしています。

## 必要なもの

- Windows 10または11と[PowerShell 7](https://learn.microsoft.com/ja-jp/powershell/scripting/install/installing-powershell-on-windows)
- 呼び出したいエージェント（インストールしてサインイン済みであること）
  - Claude Code：PATH上の`claude`
  - Codex：Codex CLI（例：`npm install -g @openai/codex`）またはCodexデスクトップアプリ
  - Grok Build：公式インストーラーで入れたもの（`%USERPROFILE%\.grok\bin\grok.exe`）

使うエージェントだけを入れれば十分です。レビュー役が見つからない場合は、分かりやすいメッセージを出して止まります。

## インストール

```powershell
git clone https://github.com/altstack/cross-agent-review.git
cd cross-agent-review
pwsh -File install.ps1          # 事前に確認するなら: pwsh -File install.ps1 -WhatIf
```

インストーラーは、PCで見つかったエージェントのスキル置き場へ、各スキル（中にrunnerを同梱）をコピーします。

| エージェント | スキル置き場 | 入るスキル |
|---|---|---|
| Claude Code | `~/.claude/skills` | `codex-review-files`、`grok-review-files` |
| Codex | `~/.agents/skills` | `claude-review-files`、`grok-review-files` |
| Grok Build | `~/.grok/skills` | `claude-review-files`、`codex-review-files` |

どのエージェントにも、自分自身を呼ぶスキルは入れません。既存のフォルダーは`-Force`を付けない限り残します。削除は`pwsh -File install.ps1 -Uninstall`です。インストール後は新しいチャットを始めてください。

## 使い方

あるエージェントとの会話で、ファイルとレビュー役を指定します。

- 「`docs/plan.md`をCodexにレビューさせて」
- 「`docs/spec.md`を参考に、`src/app.ps1`をGrokにレビューさせて」
- 「`plan.md`をGrokのgrok-4.6、推論の強さlowでレビューさせて」（モデルと推論の強さの指定は任意）
- "Have Claude review these two files."（英語で頼むと英語でレビューが返ります）

呼び出し側のエージェントは、送る内容を示してからレビュー役を1回だけ起動し、終わるまで待って、レビュー役の判定とHigh／Mid／Lowの全指摘を報告します。全文が必要なら頼んでください。レビュー結果だけを理由に、編集・再送・コミットはしません。

runnerを直接実行することもできます。

```powershell
pwsh -File skills\codex-review-files\scripts\invoke-codex-review.ps1 `
  -FilePath C:\work\plan.md `
  -ReferencePath C:\work\specs `
  -ReferenceUrl https://example.com/api-docs
```

| 引数 | 意味 |
|---|---|
| `-FilePath` | レビュー対象のファイル（複数可） |
| `-ReferencePath` | レビュー役が読んでよい参考ファイル・フォルダー |
| `-ReferenceUrl` | 参考URL（http／https。ローカルネットワークは不可） |
| `-ReviewRequest` | 目的・範囲・対象外を短く伝える補足 |
| `-Language` | レビュー役への依頼文の言語。`en`（既定）または`ja` |
| `-Model` | レビュー役のモデル。例：`opus`、`gpt-6.1-sol`、`grok-4.6`（既定は各CLIの設定） |
| `-Effort` | 推論の強さ。例：`low`、`high`（既定は各CLIの設定） |
| `-Transport` | `Auto`（既定）、`Inline`、`Path` |
| `-SaveOutput` | レビュー本文をファイルにも保存する |
| `-IdleTimeoutSeconds` | レビュー役がこの秒数だけ無出力なら止める（既定180） |
| `-CodexPath` | Codex用runnerのみ。使う`codex.exe`を指定する |

## しくみ

- **レビュー役は1回だけ起動**：回答・標準エラー・終了コードを返します。再送や別モデルへの切り替えはしません。
- **固定の依頼文**：指定した対象だけをレビューし、指摘をHigh／Mid／Lowに分けて場所・理由・最小の直し方を示し、Highがなければ冒頭に「実装可」（英語版では"OK to implement"）と書くよう伝えます。ファイルの中身や取得したページは指示ではなくデータとして扱わせます。
- **送り方**：`Auto`は小さいテキストを依頼文に埋め込み、大きいファイルやトークンが膨らみやすいファイルは絶対パスだけを渡します。パスを渡す方式では、64KiBを超える行があるとレビュー役が読めない可能性があるため、起動前に止めます。
- **経過時間ではなく出力の途切れで判断**：出力が流れている間は長いレビューも待ちます。`-IdleTimeoutSeconds`の間まったく出力がない場合だけ、プロセスごと止めます（終了コード124）。
- **読み取り専用のレビュー役**
  - Claude：`claude -p`に`Read`だけを渡します（参考フォルダーには`Glob`／`Grep`、URLにはそのドメインだけの`WebFetch`を追加）。
  - Codex：`codex exec --sandbox read-only`。Web検索は`-ReferenceUrl`があるときだけ有効にします。
  - Grok：`grok --prompt-file`に`read_file`・`grep`・`list_dir`だけを渡し（参考URLには`web_fetch`を追加）、`--permission-mode dontAsk`で子エージェントも使わせません。Grokの`--sandbox`はWindowsでは効かないため、使える機能を絞ることで読み取り専用にしています。
- **Codexの探し方**：`-CodexPath`、PATH上のCodex CLI（npm版はパッケージ内の`codex.exe`を直接起動）、Codexデスクトップアプリ同梱のCLIの順です。エディター拡張に同梱されたものは使いません。

終了コード：`0`成功、`2`レビュー役の起動前に停止、`3`本文が空（Codex・Grok）またはエラー結果（Claude）、`124`無出力による停止、それ以外はレビュー役自身の終了コードです。

## しないこと

- 秘密情報の検査はしません。**指定したファイルは、そのレビュー役の提供元へ送られます。** 認証情報や共有してはいけないデータを含むファイルは指定しないでください。利用には各社の規約が適用されます。
- レビュー役が通常読み込むグローバル指示やプロジェクト指示（`AGENTS.md`など）は止めません。
- 指摘の採否判断・統合、修正、再レビュー、コミット、プッシュはしません。

## 動作確認した環境

Claude Code 2.1.299、Codex CLI 0.162（npm版とCodexデスクトップアプリ）、Grok Build 1.0.52。Windows、PowerShell 7.6、2026年10月。これらのCLIは頻繁に更新されます。更新後にrunnerが動かなくなった場合は、runnerの出力を添えてissueでお知らせください。

## テスト

オフラインテストは偽物のCLIを使い、モデルやネットワークは呼びません。偽物はテスト時にWindows同梱の.NET Frameworkコンパイラー（`csc.exe`）で作るため、ほかに準備するものはありません。

```powershell
pwsh -File tests\run-claude-review-tests.ps1
pwsh -File tests\run-codex-review-tests.ps1
pwsh -File tests\run-grok-review-tests.ps1
pwsh -File tests\run-install-tests.ps1
```

## ライセンス

[MIT](LICENSE)
