# monitor council の fork 空振り（lite hint 無視）を PreToolUse hook で機械的に防ぐ

## 背景（合意済み・掘り直し不要）

Enterprise 契約後のトークン使用量調査で `flywheel:monitor` の呼出頻度の高さが判明し、
実データ（`monitor-verdicts.csv`）を見ると full council が 15/21 件（約70%）と過半数。
「lite/標的判定の閾値（`FLYWHEEL_MONITOR_LITE_DIFF=250`）を上げる」対策を検討したが、
実データで `diff=75` が `full` にも `lite` にもなっており、閾値そのものは正しく機能して
いる（lite 対象と判定されるケースがある）ことを示している。閾値を上げても効果は薄い。

真因は別にある。今回の goal（v0.8.46）自体の作業中、`Skill: flywheel:monitor` を
Skill tool 経由で呼んだところ、loop-driver の steer が「diff 54行・lite council 可」と
明示していたのに、実際には 3レンズ full fan-out で走った（`monitor-verdicts.csv` に
`diff=54, mode=full` として2件記録）。これは `skills/monitor/SKILL.md` の既存 Gotcha
「[2026-06-15] forked 実行（context:fork）が verdict を出さず空振りする」に記載済みの
既知バグで、対策（「overseer の手順を呼び出し側で inline 実行する」）も書かれているが、
文書の注意書きだけでは実運用（このセッション含む）で守られない。

→ **PreToolUse hook で機械的に防ぐ。** loop-driver の lite/標的 hint 判定ロジック
（`watch_focus` / `last_drift` / diff 計算、`hooks/loop-driver.sh` の `monitor_hint()`）
は state.json に保存されずその場で計算して消えるため、hook 側で同じ判定を複製すると
ロジックが2箇所に分散し将来の drift 元になる。**ロジック複製はせず、
`Skill: flywheel:monitor` の呼出し全件を deny で機械的にブロックする**（ask ではなく
deny — 対策（inline 実行）は fork したケース全てで常に同じであり、fork してよい
ケースは無い。監視 council レビュー時に「ask だと monitor は最頻出 multi-agent 操作
（139回/5週）なので毎回人間確認を挟むことになり、HOTL の『人間は on-loop』原則に
逆行する」との指摘を受け、deny に変更した。過検知（lite hint が出ていないときも
deny）は許容——判定を誤っても redirect 先の対策は変わらないため）。

## 変更内容

### 1. 新規 `hooks/monitor-fork-guard.sh`（PreToolUse・matcher: Skill）

`hooks/skill-logger.sh`（既存の PreToolUse・matcher: Skill hook）と同じ入力形式
（stdin の JSON、`jq -r '.tool_input.skill // empty'`）を使う。

- `fw_hook_guard`（既存関数）で bypass/dormant を素通し。
- `tool_input.skill` が `flywheel:monitor` 以外なら何もしない（disk I/O 無しの stdin
  判定なので、state.json を読む phase 判定より先に行う——大半の Skill 呼出しをここで
  安く抜ける）。
- `fw_phase` が `eval` または `polish` 以外なら何もしない（monitor council はこの2
  phase でのみ呼ばれる想定・他 phase は対象外）。
- 上記2条件を満たすときのみ、以下の JSON を stdout に出し `exit 0`（ask ではなく
  deny decision — `hooks/*.sh` 内に前例が無いため、`~/.claude/settings.json` の
  sqlite3 破壊的操作 hook と同じ `hookSpecificOutput` 形式を踏襲する）:
  ```json
  {"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Skill tool 経由の flywheel:monitor 呼出しは forked execution になり、loop-driver の lite/標的 council hint が無視されて常に full 3レンズ fan-out にフォールバックする既知バグがある（SKILL.md Gotcha参照）。overseer の手順（context 収集 → drift-observer を fan-out → 集約 → flywheel monitor-set）を呼び出し側で inline 実行してください。"}}
  ```
- ロジック複製をしないため、実際に lite hint が出ているかどうかは判定しない（呼出し
  全件で deny）。過検知（hint が無いときも deny される）は許容スコープ内——対策は
  常に inline 実行なので、誤判定でも redirect 先は変わらない。

### 2. `hooks/hooks.json` に配線

既存の `"matcher": "Skill"` エントリ（`skill-logger.sh`）に **同じ matcher 内で
hooks 配列にもう1エントリ追加**する（同一 PreToolUse イベントに対する複数 hook は
それぞれ実行される・既存の `design-gate.sh` 追加時と同じパターン）:
```json
{
  "matcher": "Skill",
  "hooks": [
    { "type": "command", "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/skill-logger.sh", "timeout": 5000 },
    { "type": "command", "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/monitor-fork-guard.sh", "timeout": 5000 }
  ]
}
```

### 3. `skills/monitor/SKILL.md` の Gotcha 更新

既存の Gotcha「[2026-06-15] forked 実行（context:fork）が verdict を出さず空振りする」の
末尾に一文追記: 「[2026-07-21 追記] `hooks/monitor-fork-guard.sh`（PreToolUse）が
eval/polish phase での `Skill: flywheel:monitor` 呼出し全件を deny で機械的にブロック
するようになった（v0.8.47）。fork してよいケースは無いため ask ではなく deny——deny が
出たら overseer の手順をそのまま呼び出し側で inline 実行する。」

### 4. テスト（`test/monitor-fork-guard.sh` 新規）

`test/chain-lib.sh` の環境分離ヘルパを使う。

- C1: phase=eval で `Skill(flywheel:monitor)` 相当の PreToolUse 入力（`tool_input.skill
  = "flywheel:monitor"`）を hook に流すと、`hookSpecificOutput.permissionDecision ==
  "deny"` を含む JSON が stdout に出ること。
- C2: phase=polish でも同様に deny が出ること。
- C3: phase=implementing（対象外 phase）では deny が出ない（stdout 空 or 非該当）こと。
- C4: `tool_input.skill = "flywheel:next"`（対象外 skill）では phase=eval でも deny が
  出ないこと。
- C5: `FLYWHEEL_OFF=1` で無効化されること（`fw_hook_guard` 経由）。
- `test/run-all.sh` に自動で乗る。

## 非スコープ

- monitor cap 値（現在8）の見直し — 別 goal
- `drift-observer` の Haiku 化 — 別 goal（`model: sonnet` は CI assert 済みの不変条件
  `test/agent-model-tiering.sh` があり、変更は別途の検証が必要）
- loop-driver.sh の lite/標的 hint 判定ロジックの変更・複製 — 今回は「呼出し全件で
  deny」に留め、hint 判定ロジックは1箇所（loop-driver.sh）のまま保つ
- deny された後にモデルが実際に inline 実行するかどうかの強制（deny は Skill 経由の
  fork 実行を防ぐだけで、モデルが inline 手順を正しく踏むかまでは制御しない）

## 完了条件（eval）

```
bash test/run-all.sh
```

新規 `test/monitor-fork-guard.sh` が上記アサートで合格し、既存テストに regression が
無いこと。
