# requirements — FR-35 / HOTL phase2: start 経路 auto-chain

## 背景

HOTL（human in → on the loop）の北極星: 人間を loop の必須ステップ(in)から監督者(on)へ。
合意済みの形は **調べる = loop（自動）/ 決める = grill-me（人間）/ 判定 = 独立（monitor）**。
順序原則「verification 独立化が先」は v0.8.15（FR-34: verification→monitor 統合・runtime レンズ +
overseer smoke）で満たした。これを土台に start 経路を緩める。

## 現状（コードで裏取り済み）

`hooks/loop-driver.sh:216-221`: done → backlog の次が `entry == "start"`（要件を一から掘る goal）の
とき、`fw next` で pop はするが **`exit 0` で人間に丸ごと hand-back**（"requirements.md と design.md を
書いてください"）。adopt 経路（合意済み設計）は `exit 2` で連鎖続行するのと非対称。
= start 経路は human-**in**（loop が止まり人間が要件作業を全部やる）。

`loop-driver` は **Stop hook**（非対話）。AskUserQuestion を自分では呼べない。よって「人間に pop」は
**`exit 2` + steer**（次ターンのモデルへの指示）で実現する＝adopt chain と同じ機構。

## やること

start 経路 auto-chain を hard-stop から「**調査自動 + 決め所だけ grill して続行**」へ。done→次が
start goal のとき:

1. **go/no-go gate**: まず人間に「この goal を今掘りますか?」を grill-me（human-on の決め所）。
2. **go なら discovery 自動**: discovery（曖昧なら deep-interview→discovery-council）で
   requirements.md + design.md を draft。**過程で出た判断**（スコープ/トレードオフ/優先度/命名/
   案の選択）**だけ grill-me**。事実は self-answer（v0.8.12 の「判断は self-answer しない」を steer に明記）。
3. **続行**: design ゲート合格→実装→eval→done→（backlog が残れば）連鎖。
4. **no-go なら**: discovery せず停止。goal は loaded(designing) のまま human に返す（後で再開 or reset）。

## 決定（grill 済み・2026-06-18）

- **連鎖の既定**: デフォルト ON。ただし**連鎖前に go/no-go を grill**（vague な start goal の drift を
  人間が一段目で止められる）。`FLYWHEEL_NO_CHAIN=1` で従来 hard-stop（実際は pop せず stop）に戻せる。
- **pop 粒度**: discovery が requirements を draft する過程で出た**判断だけ grill**したら自動続行
  （requirements draft 後に必ず1回止める案は不採用＝human-in 寄りなので）。

## スコープ

- IN: `hooks/loop-driver.sh` の start 分岐（216-221）/ steer 文言 / `fw_log_usage "steer:start-chain"` /
  `test/`（start-chain.sh 新規 + adopt-chain.sh ケース2 の期待値更新）。
- OUT: adopt 経路の挙動・design ゲート・monitor・新 CLI コマンド。NO_CHAIN の挙動（pop せず stop）は不変。

## 完了条件

- start goal で done 到達 → `exit 2` + go/no-go・discovery・「判断は self-answer しない」を含む steer。
- `FLYWHEEL_NO_CHAIN=1` で従来どおり pop せず `exit 0`（backlog 残）。
- adopt 経路・backlog 空は退行なし。
- 自動検出 eval（test）が緑。
