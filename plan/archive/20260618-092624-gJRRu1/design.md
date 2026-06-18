# design: adopt/start/add の `!` 行 args sanitize（single-quote 包み）

v0.8.19 FR-39 dogfood で実踏したバグの修正。FR-40。

## 背景（なぜ）

`/flywheel:adopt`・`/flywheel:start`・`/flywheel:add` の `!` 動的注入行が `$ARGUMENTS` を
**double-quote** でシェルに埋める（`commands/adopt.md:8` / `start.md:8` / `add.md:10`）。
`$ARGUMENTS` はスラッシュコマンドのプリプロセッサが **シェル実行前に literal 置換** するので、
args に ASCII シェルメタ文字（バッククォート＝コマンド置換 / ASCII 引用符＝unmatched / ASCII 括弧 /
`$`）が入ると `if [ -n "..." ]` 行が **parse error**（行全体が実行前に弾かれ skill 起動失敗）。

これは **parse error**（実行前に行が弾かれる）なので `||`/フォールバックでは実行時に拾えない。
テキストを「コードとして解釈されない」形にするしかない。`next.md` は `$ARGUMENTS` 不使用で安全。

## 変更点（single-quote 包み・最小スコープ）

3コマンドの `!` 行で `$ARGUMENTS` の囲みを **double-quote → single-quote** に:
- `commands/adopt.md:8` — `[ -n "$ARGUMENTS" ]` と `adopt "$ARGUMENTS"` を `'$ARGUMENTS'` に
- `commands/start.md:8` — 同上（`start "$ARGUMENTS"`）
- `commands/add.md:10` — `[ -z "$ARGUMENTS" ]` を `[ -z '$ARGUMENTS' ]` に

single-quote は `$ARGUMENTS` 置換後の literal テキストをシェル解釈から保護する
（プリプロセッサ置換が先なので展開は不要・むしろ抑止したい）。各 `!` 行に **既知の限界を1行コメント**:
args に literal `'` が入ると壊れる（ゴール文では稀・bulletproof 化は非スコープ）。

**検証が要る前提（実装時に潰す）**: プリプロセッサが `$ARGUMENTS` を **single-quote の中でも literal 置換する**こと
（テキストマクロなので囲みに依らず置換される想定。もし single-quote 内で置換されないなら fix が無効化＝
heredoc 案へ切替）。実装後に実コマンド起動 or 同等の検証で確認する。

## 非スコープ

- `next.md`（args 不使用・安全）。
- heredoc 等での bulletproof 化（literal `'` 対応）— エッジすぎ・複雑化回避で defer。
- **grill closing-checkpoint を AskUserQuestion 化（FR-39 phase 2）** — 別 goal。done 後に ROADMAP 計上。

## 完了条件（eval）

`test/adopt-args-sanitize.sh`:
1. 3コマンドの `!` 行が `'$ARGUMENTS'` 形であること・`"$ARGUMENTS"` を含まないこと（grep）。
2. 機能: hostile な文字列（unmatched 引用符・バッククォート等）を single-quote 形に流すと `bash -n` が
   **通る** / 同じ文字列を旧 double-quote 形に流すと `bash -n` が **落ちる**（＝修正が効いてる証明）。

```bash
bash test/adopt-args-sanitize.sh
```
