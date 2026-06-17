# grill が判断を必ず聞く + ROADMAP をメイン機能に — design

## Context

2点。**(1)** grill が「コードで答えが出るなら聞くな（肝）」を *事実* だけでなく *判断* にまで広げて
self-answer し、ユーザーに質問しなくなる（実会話で発生）。**(2)** ROADMAP.md が flywheel の改善管理で
頻出し、実質「共有 backlog の源」になっているが、backlog（adopt chain）との連携が運用任せで中核化していない。
両者は繋がる: ROADMAP 項目を取り込む `/flywheel:add` の grill が判断を聞くほど、取り込む phase の質が上がる。

## 方針

- **grill の事実/判断峻別**: 「self-answer は *事実*（コードに答えがある）のみ。*判断*（スコープ/トレードオフ/
  優先順位/命名/どの案か）はコードに答えが無いので必ず聞く。迷ったら聞く側に倒す」を grill・plan-steer・add に明文化。
- **ROADMAP メイン機能化（源→backlog 導線）**: ROADMAP.md は手動 .md のまま、`/flywheel:add`（軽量 grill で
  phase 化）を取り込み口に。`ROADMAP（源）→ /flywheel:add → backlog → /next → 実装` を中核ワークフローとして
  明文化。新コマンド・テーブル parse は作らない。

## Tasks（Boundary / Depends / Done）

- **T1 grill が判断を必ず聞く** | Boundary: `skills/grill/SKILL.md`（原則+Gotcha）, `hooks/plan-steer.sh`（FR-24）, `commands/add.md`（軽量 grill） | Depends: - | Done: 3ファイルに「事実/判断の峻別（判断は必ず聞く・迷ったら聞く）」の記述がある
- **T2 ROADMAP をメイン機能に** | Boundary: `ROADMAP.md`（ヘッダにワークフロー + 状態列に「backlog 中」）, `skills/guide/SKILL.md`（ROADMAP→add→backlog→next の導線） | Depends: -（T1 と別ファイル・並列可） | Done: ROADMAP.md にワークフロー記述、guide に ROADMAP からの取り込み導線

## 非スコープ

- ROADMAP の CLI 化（`flywheel roadmap add/list/done`）・markdown テーブルの parse 取り込み。手動 .md + /add で繋ぐ。
- 既存 grill/plan-steer/add の他の挙動変更（峻別の明文化のみ。質問の下限設定はしない）。
- `/adopt` auto-chain（別 phase）。

## 完了条件（eval）

```
bash -n hooks/plan-steer.sh
grep -qiE '判断' skills/grill/SKILL.md
grep -qiE '判断' hooks/plan-steer.sh
grep -qiE '判断' commands/add.md
grep -qiE 'ROADMAP' skills/guide/SKILL.md
grep -qiE 'backlog' ROADMAP.md
```

合格 = plan-steer.sh の構文 OK・3箇所(grill/plan-steer/add)に「判断」の峻別記述・guide に ROADMAP 導線・ROADMAP.md に backlog 連携記述。
