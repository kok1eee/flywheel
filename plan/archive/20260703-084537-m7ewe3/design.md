# design: hook 発火の live positive control（FR-54・heartbeat + greeter warn + steer 1節）

## 背景・問題

FR-53 の hooks-wiring ガードは **repo 側**の配線破れ（カンマ matcher・script 消失）しか観測できず、
**host（Claude Code）側の hook 意味論変更による fail-open** は residual として残った（ROADMAP FR-53 行）。
2.1.191 のカンマ matcher バグが示したのは「**特定 matcher / 特定 hook だけが無音で死ぬ**」class で、
design-gate（PreToolUse block）がこれを踏むと設計ゲートが**無音で蒸発**する（eval も test も緑のまま）。

対策は sensors-first の相似形: **発火そのものを痕跡として記録し（heartbeat）、痕跡の欠如を別 hook
（greeter）が warn する** live positive control。greeter 自身も hook なので「全 hook 死」は原理的に
検知できないが、それはユーザーが flywheel の完全沈黙で気づく。ここで守るのは **部分死**（greeter は
生きているが design-gate だけ死んだ = まさに 2.1.191 の実 class）。

あわせて FR-53 altitude 指摘の消化: loop-driver の指紋不一致 steer に「遅延 council レポート対応
なら revert + improvements.md 退避」の 1 節を追記（違反検知の瞬間の live steer が remediation を運ぶ）。

## 方針

### 1. heartbeat（common.sh ヘルパ + design-gate 発火点）

- `fw_touch_heartbeat <name>`（`hooks/lib/common.sh`・`_fw_log_csv` の隣）: `$(fw_data_dir)/heartbeat-<name>`
  を **touch**（mtime 更新）。**追記 CSV にしない**——design-gate は Edit/Write 毎に発火する高頻度 hook
  なのでサイズ無成長の mtime 方式。mkdir/touch 失敗は `|| return 0`（observation-only・門を壊さない）。
- 呼び出し: `design-gate.sh` の `fw_hook_guard` 通過直後（= flywheel active で実際に発火した証明点。
  dormant/bypass は guard で抜けるため touch されない）。対象は **fail-open な design-gate のみ**
  （loop-driver は死ねば done が止まる＝自己顕在なので不要）。
- heartbeat は fw_data_dir（plugin 全体で共有・リポ外＝FR-50 指紋非影響）。配線と host 意味論も
  plugin 全体で共有なので、**故障ドメインと観測ドメインが一致**する（リポ跨ぎの mtime 更新は仕様）。

### 2. greeter warn（fw_heartbeat_staleness）

- `fw_heartbeat_staleness`（common.sh・`fw_evolve_staleness` と同型 = 失敗しても greeter を壊さず
  常に return 0・非該当は無音）。warn 条件（**AND**）:
  - `fw_state_exists` かつ phase が **implementing / eval / polish**（implementing 到達は design-gate の
    `fw_advance` 経由でしか起きない＝**発火済みの必然**がある phase。designing / spec-ready は未発火が
    正常あり得・done は編集が止まるので対象外）
  - heartbeat ファイルが**存在しない**、または mtime が閾値（既定 **7 日**・`HEARTBEAT_STALE_DAYS` で
    上書き可）より古い
- warn 文言（1 行・active 再アンカーに追記）: 「⚠️ design-gate の発火痕跡が無い/古い（設計ゲートが
  host 側で無音死している可能性）。`bash test/hooks-wiring.sh` で repo 側配線を確認し、直近の
  Claude Code 更新を疑う」
- 限界を明記（residual）: 全 hook 死は greeter ごと死ぬため検知不能（ユーザーが完全沈黙で気づく領域）。
  閾値方式なので死後 7 日間は検知穴（v1 は「気づける確率を 0 から上げる」ことが目的）。

### 3. loop-driver 指紋不一致 steer の 1 節（FR-53 altitude 指摘の消化）

`loop-driver.sh` の stale-clean steer（「clean 記録後にコードが変わりました…」）に追記:
「変更が遅延 council レポートの消化なら revert して指摘を improvements.md へ退避する選択肢もある
（monitor SKILL.md Gotcha 参照）」。ロジック変更なし・message 1 節のみ。

## Boundary（触る範囲）

- `hooks/lib/common.sh`: `fw_touch_heartbeat` / `fw_heartbeat_staleness` 新規（fw_evolve_staleness 隣）
- `hooks/design-gate.sh`: guard 通過直後に touch 1 行
- `hooks/session-greeter.sh`: active 分岐に staleness warn 1 行（evolve_line と同型の合成）
- `hooks/loop-driver.sh`: 指紋不一致 steer の message 1 節（ロジック不変）
- `test/heartbeat.sh` 新規 1 本（chain-lib 隔離ハーネス・run-all が自動で拾う）
- 出荷規約: README 機能・Changelog / ROADMAP（FR-54 行 + FR-53 residual 行の更新）/ version **v0.8.35**
  （plugin.json / marketplace.json / README 冒頭）
- 非スコープ: design-gate 以外への heartbeat 展開（必要が実証されてから）、全 hook 死の検知（原理的に
  不能）、heartbeat の可視化/集計、hooks.json の変更

## 後方互換・degrade

- heartbeat の touch/警告はすべて observation-only: touch 失敗・データ領域 read-only・ファイル欠落の
  いずれでも design-gate / greeter の既存挙動は不変（`|| return 0` / `|| true`）。
- 既存 test は hook 挙動（exit code / 遷移）だけを見ており、heartbeat 追加で壊れない（chain-lib は
  CLAUDE_PLUGIN_DATA を /tmp に隔離済み＝本番 heartbeat も汚さない）。

## 完了条件（eval）

```
bash test/run-all.sh
```

exit 0。新テスト `test/heartbeat.sh`（chain-lib）が満たすべき性質:

1. C1: active state（implementing）で design-gate を実入力（Edit の PreToolUse JSON を stdin）で起動
   → exit 0 のまま `$CLAUDE_PLUGIN_DATA/heartbeat-design-gate` が生成される。
2. C2: phase=implementing で heartbeat を削除 → session-greeter の出力に warn が含まれる。
   heartbeat を touch し直す → warn が消える（無音）。
3. C3: dormant（state なし）→ design-gate は touch しない（guard で抜ける）・greeter も warn しない。
4. C4: データ領域を書き込み不能にしても design-gate の exit code / ブロック挙動は不変
   （observation-only の実証）。
5. 既存 test 全緑（run-all 集約）。

## 検証の落とし穴（前例由来）

- greeter は `set -euo pipefail` + `emit` で exit する構造。staleness 呼び出しは `|| true` 付きで
  合成し、どんな失敗でも greeter を落とさない（fw_evolve_staleness の流儀）。
- design-gate は `exit 2`（block）経路を持つ。heartbeat の touch は block 判定の**前**（guard 直後）に
  置き、「発火した」の意味論を判定結果と独立にする。
- mtime 比較は `find -mtime` でなく epoch 比較（`stat -c %Y`）で行い、bash 演算のみで判定
  （mawk/gawk 差異・GNU/BSD stat 差異は CI=ubuntu / 本番=AL2023 とも GNU なので `-c` で統一）。
- test で greeter を起動するときは SessionStart hook として stdin 不要・出力 JSON の
  additionalContext を jq で剥がして assert する。
