---
description: 戦略・分析系の難問に judge panel（全 Opus 4.8）でトップレベルの回答を出す。切り口を動的設計→候補案を並列生成→審査→勝者に接木して統合。計7〜9体の Opus が走る高コストコマンド（明示起動＝Workflow の opt-in）。
argument-hint: "\"<戦略・分析系の問い>\""
---

`Skill: flywheel:ultrawork` を起動し、`$ARGUMENTS` を問いとして SKILL.md の手順を実行してください:
問いの受領（曖昧なら 1〜2 問だけ確認）→ canonical Workflow を1回（全 agent が opus 固定）→
統合回答を会話に直接提示（判断過程を透明化・長大なら Artifact 併記）→ 失敗時は明示フォールバック。
手順の実体は skills/ultrawork/SKILL.md が正（ここは薄い導線のみ・重複させない）。
