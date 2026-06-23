# design: chain の goal 間 auto-checkpoint（FR-46）

adopt chain（FR-33）が done→次 goal で commit せず、連続 done が1つの未コミット change に bundle され
履歴粒度が潰れる問題を、**done→chain 境界で jj の checkpoint（describe + new）** を自動挿入して解消する。

## 背景・要件（grill 済みの判断）

- **問題**: chain 連鎖時、goal N の work と N+1 の work が同じ working change に混ざる（本セッションでも
  CI/intent-router/chain-checkpoint を手で `jj new` 分離した＝この手作業の自動化）。
- **スコープ判断（grill）**: **jj のみ**対応（このリポ/ユーザーは jj 専用・git auto-commit は committal で YAGNI）。
  git リポは **1行 note を出して skip（degrade・surprise commit しない）**。
- **既定**: **ON**。`FLYWHEEL_NO_CHECKPOINT=1` で無効化（`FLYWHEEL_NO_CHAIN` / `NO_FUSE` と同じ escape-hatch）。
- **message**: goal から自動生成（`chore: chain checkpoint — <goal 1行目・72字>`）。
- **タイミング**: done 確定 → `fw_archive_plan` の後、`next`（N+1 起動）の**前**。backlog>0（連鎖がある）時のみ。
  最後/単独 goal は従来どおり人間が describe（bundle 問題は連鎖時のみ発生）。
- **C-2 整合**: checkpoint は **hook（loop-driver）が VCS 操作**する（モデルではない）。`.flywheel/` state は
  触らないので C-2 不変。jj describe/new は op log で可逆＝低リスク。境界は file 編集が止まる安全なタイミング。

## 変更点

### 1. `hooks/lib/common.sh` — `fw_chain_checkpoint` + `fw_checkpoint_msg`

- `fw_chain_checkpoint`: `FLYWHEEL_NO_CHECKPOINT=1` なら即 return。`jj root` が無ければ git とみなし
  1行 note を stderr に出して return（degrade）。jj なら goal を `fw_get '.goal'` で取り、
  `jj describe -m "<msg>"`（@＝完了 goal の change をラベル）→ `jj new`（N+1 用の空 change）。
  各 jj コマンドは失敗しても return 0（checkpoint 失敗で loop を止めない・best-effort）。
- `fw_checkpoint_msg <goal>`: goal の1行目を72字で切り `chore: chain checkpoint — <...>` を返す（repo 非依存）。

### 2. `hooks/loop-driver.sh` — chain 境界で呼ぶ

`n="$(fw_backlog_count)"` の `if [[ "$n" -gt 0 && NO_CHAIN != 1 ]]` 直後・`"$FW_CLI" next` の**前**に
`fw_chain_checkpoint` を1行挿入。これで goal N を commit してから N+1 を起動（baseline=@-=N の change）。

### 3. `test/chain-checkpoint.sh`（新規）

- **jj path**: mktemp に `jj git init` → 最小 state（`.goal`）+ work → `fw_chain_checkpoint` 呼び出し →
  `@-` が `chain checkpoint` message で described・`@` が空の新 change、を assert。
- **git path**: mktemp git repo で呼び出し → HEAD が不変（commit していない）・エラー終了しない（degrade）を assert。

### 4. docs / version

- `README.md` env 表に `FLYWHEEL_NO_CHECKPOINT` を追記、Changelog に v0.8.26 エントリ。version v0.8.26（plugin.json
  + marketplace.json 2箇所 + README 冒頭）。`ROADMAP.md:59` を `✅ 実装済（v0.8.26・FR-46）` に。

## 非スコープ

- **git の auto-commit**（degrade に留める・要望が出たら follow-up）。
- 単独/最後 goal の checkpoint（bundle は連鎖時のみ＝対象外）。
- adopt 経路の「着手前 go/no-go checkpoint」（FR-33 follow-up 別件・ROADMAP:54 に記載）。

## 完了条件（eval）

```bash
bash test/run-all.sh
```
