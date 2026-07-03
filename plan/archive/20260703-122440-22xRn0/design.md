# design: fan-out skill の背景デフォルト棚卸し（FR-55）+ monitor-lens-csv テスト網強化の同乗

## 背景・問題

2.1.198 の subagent 背景デフォルト化への対応は FR-53 で monitor council のみ行った。他の fan-out
面も同じ構造リスク（spawn→ターン終了→結果が漂着し集約されない）を持つが未棚卸しだった
（improvements.md 2026-07-03）。棚卸しの判定基準は FR-53 で確立済み:

- **binding**（結果を同一ターンで集約して判定・成果物に使う）→ `run_in_background: false` を明記
- **advisory**（結果を後続ターンで拾うだけ）→ 背景のままで良い旨を明文化

## 方針

### 1. 棚卸し結果（grep で確定した事実）

| fan-out 面 | 分類 | 対応 |
|---|---|---|
| monitor 観測者 3 体 | binding | **FR-53 で対応済み**（sync 明記 + guard） |
| discovery-council メンバー 3 体（researcher/analyst/scout） | binding（SendMessage 相互検証→集約→Step 3 曖昧点確認が同一フロー） | SKILL.md Step 2 に方針 1 行 + reference.md の 3 テンプレに `run_in_background: false` を追記 |
| design の designer 1 体 | binding（design.md 生成を待って validate へ進む） | SKILL.md Step 1 テンプレに 1 行 |
| verification の証拠収集子（FR-26 nested） | binding（親が同一ターンでエビデンスを照合して判定） | SKILL.md 委譲節に 1 行 |
| advisory な fan-out | 現 flywheel skill には存在しない | 「調査結果を後続停止で拾うだけなら背景可」の一般則を discovery-council の方針行に含める（将来の継続監視等はこの分類） |

### 2. hooks-wiring ガードの対象拡張（notes の判断事項→採用）

`test/hooks-wiring.sh` の sync 前提ガードを、新たに sync 明記する 3 ファイルへ拡張:
- monitor SKILL.md は既存の **count==1 厳格 assert** を維持（anchor 一意性）
- 新規 3 ファイル（discovery-council/reference.md・design/SKILL.md・verification/SKILL.md）は
  **存在 assert（≥1）** に留める（テンプレ数の増減で brittle にしない。0 になったら＝指示消失で fail）

### 3. 同乗: monitor-lens-csv テスト網強化 3 点（FR-52 council low note の消化）

- C1b: timestamp 列の形式 assert（`^[0-9]{4}-…Z,` を先頭データ行で検証。現状はヘッダ名しか見ていない）
- C7: sanitize 経路の演習（`--lens 'a"b,c'` → `ab|c` に正規化されて記録される）
- C8: **既存 CSV への append 失敗**経路（CSV 自体を chmod 444）でも exit 0 + verdict 記録
  （C4 は「新規作成失敗」しか踏んでいない）

## Boundary（触る範囲）

- `skills/discovery-council/SKILL.md` + `skills/discovery-council/reference.md`（sync 明記）
- `skills/design/SKILL.md` / `skills/verification/SKILL.md`（各 1 行）
- `test/hooks-wiring.sh`（ガード対象 3 ファイル追加・存在 assert）
- `test/monitor-lens-csv.sh`（C1b/C7/C8 追加）
- 出荷規約: README Changelog / ROADMAP（FR-55 行）/ version **v0.8.36**（plugin.json / marketplace.json / README 冒頭）
- 非スコープ: モデル tier の固定（observer 系=Sonnet はユーザーの運用 preference＝memory 管理。
  plugin は model-agnostic に inherit を維持）、背景 fan-out を活用する新機構（継続監視等・ROADMAP 級）
- ~~agent 定義（agents/*.md）の変更も当初非スコープ~~ → **council 採択で範囲拡張**（下記節参照。
  background: true 残骸除去 + 調査の委譲節への sync 明記）

## polish（simplify レビュー採択）

- 理由文の重複解消: 全文の機序説明は ROADMAP「機構メモ」（binding/advisory 基準の正）と monitor
  SKILL.md に集約し、design / verification / reference.md の 3 テンプレは 1 行タグ + 参照に統一。
- reference.md のガードを「sync 数 == subagent_type 数」の self-adjusting assert に強化
  （≥1 だと一部テンプレだけの無音消失を素通りする altitude 指摘の採用。テンプレ追加には自動追従）。
- chmod → 実行 → 戻す → assert のイディオムが 3 箇所目（rule-of-three 到達）: chain-lib への
  ヘルパ抽出は diff 外（heartbeat.sh は前 commit）に及ぶため improvements.md へ退避。

## council 採択（drift implementing・observer-requirement conf88/high）

- 棚卸しが agents/ 側を見落とした: `agents/researcher.md` frontmatter の `background: true` と
  discovery-council SKILL.md の既存 Gotcha（researcher 非同期運用）が新 sync 方針と正面矛盾のまま
  残存していた。修正の grep 追跡でさらに 6 agent（code-explorer / oss-scout / convention-scout /
  architecture-mapper / market-researcher / pattern-observer）にも同残骸を発見——いずれも FR-26
  nested 委譲 / Phase B 偵察で親が同一ターン集約する binding 用途。**agents/ 計 7 ファイルから
  `background: true` を除去**（非スコープだった agents/*.md を同一 class の残骸除去に限り範囲拡張。
  2.1.198+ では frontmatter 固定でなく、advisory にしたい呼び出し側が都度 run_in_background: true
  を渡すのが正）。discovery-council の Gotcha は sync 前提の文面に更新（旧運用は廃止と明記）。
- Note 消化: discovery-council Step 2 の説明段落を 1 行タグ + ROADMAP 機構メモ参照に圧縮
  （requirement F002 / progress F002。理由文の正は ROADMAP 機構メモに一本化）。
- 再 council Note 消化（conf78=採用基準未満だが実在・安価）: nested 委譲の呼び出し側にも sync を
  明記——researcher / analyst / scout の「調査の委譲」節に 1 行 + discovery-council Step 2 の nested
  行に一言。hooks-wiring に agents/ の background: true 再混入ガード（negative assert）と 3 agent
  ファイルの sync 存在 assert を追加。Boundary の非スコープ記述と採択の自己矛盾も注記で解消。

## 後方互換・degrade

- SKILL.md/reference.md の変更は指示の明確化のみ（手順・出力 schema 不変）。
- hooks-wiring の追加 assert は現ツリーで即緑（sync 明記と同 change で入るため）。
- lens テスト追加は既存 C1-C6 に非干渉（末尾追加・状態を汚す場合は都度リセット）。

## 完了条件（eval）

```
bash test/run-all.sh
```

exit 0。満たすべき性質:

1. binding な fan-out 4 面すべてに `run_in_background: false` の明記が存在し、`test/hooks-wiring.sh`
   がその存在を機械観測する（monitor は count==1 厳格・他 3 ファイルは ≥1）。
2. `test/monitor-lens-csv.sh` が timestamp 形式 / sanitize（引用符除去・カンマ→パイプ）/ 既存 CSV
   append 失敗の 3 経路を実走で assert する。
3. 既存 test 全緑（run-all 集約）。

## 検証の落とし穴（前例由来）

- reference.md のテンプレは YAML 風 prose なので、`run_in_background: false` は `subagent_type` の
  隣に置き、ガードは**ファイル単位の存在 assert** に留める（行数 count は brittle）。
- C8 は CSV ファイル自体を chmod 444（C4 のディレクトリ 555 とは別経路＝ヘッダ作成でなく append 失敗）。
  chmod 戻しを fail 前に行う（monitor-lens-csv C4 の既存イディオム踏襲）。
- C7 の期待値: `tr -d '"\n' | tr ',' '|'` に対し `a"b,c` → `ab|c`。grep は BRE リテラル `|` で書く。
