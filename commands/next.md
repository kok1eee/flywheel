---
description: backlog の次の goal を起動する（adopt chain の逐次実行）。dormant/done のとき先頭を pop し、積んだ経路（start/adopt）で開始。
argument-hint: ""
---

backlog の先頭 goal を起動します（積んだ経路を尊重: `--adopt` で積んだものは掘らず結晶化起動）。

!`"${CLAUDE_PLUGIN_ROOT}/bin/flywheel" next`

起動した goal の phase に応じて進めてください:

- **adopt 経路で起動した場合**（掘らない）: 会話 or `.claude/journal.md` の合意を `plan/design.md` に結晶化してください（「## 完了条件（eval）」も設計）。`.md` のみの非コード goal なら、最初の implementing 昇格は `flywheel go`。
- **start 経路で起動した場合**: まず `plan/requirements.md` と `plan/design.md` を書く（曖昧なら `/flywheel:deep-interview` → `/flywheel:discovery-council`、要件があるなら `/flywheel:design`、叩くなら `/flywheel:grill`）。

design.md を書くと validate-plan が自動実行され、合格で実装ゲートが開きます。以後は実装 → eval → polish → done まで自動で回ります。**done 後は backlog があれば次の goal が自動起動します（adopt chain・FR-33）** — adopt 経路ならそのまま設計→実装へ連鎖し、backlog を全部一気に消化します。次が start 経路（要件を一から掘る）のとき、または `FLYWHEEL_NO_CHAIN=1` のときだけ手動 `/flywheel:next` が要ります。

`backlog は空です` と出たら、先に積んでください: `/flywheel:add "<goal>" --adopt`（複数 phase を一気に積めます）。
