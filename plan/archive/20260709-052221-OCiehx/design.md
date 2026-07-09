# design: agent model tiering（観測・偵察・レビュー専任 agent の model: sonnet 静的固定）

## 背景・問題

- ユーザーがメインループを Fable 5 に移行（2026-07-09 `/model`）。flywheel の fan-out agent が
  `model: inherit` のままだと、監視 council の観測者 3 体等が **Fable 5 で走りコストが跳ね上がる**
  （monitor は goal ごとに毎回走る＝最頻の fan-out 面）。
- 7/3 に memory `subagent-model-tiering` で「観測・判断のみの subagent は spawn 時に
  `model: "sonnet"` を明示」という**運用ルール**を決めたが、これは prompt-level（spawn する
  モデルが memory を思い出せば効く）で機械強制が無い。flywheel の思想（C-2: モデルの記憶や
  自己申告に頼らず機械が強制する）に照らすと、frontmatter への静的固定が正。
- 現状はまだら: `agents/*.md` 15 ファイル中、sonnet 固定済み 6（convention-scout /
  market-researcher / oss-scout / pattern-observer / security-reviewer / debugger）、
  inherit のまま 8（drift-observer / architecture-mapper / code-explorer / critic / researcher /
  scout / analyst / designer）、model 指定なし 1（capabilities＝spawn されない reference doc）。

## 方針（2026-07-09 会話 + 軽量 grill で確定）

判定基準は「**考える部分（設計・要件の生成）か、視て判断を返すだけか**」:

| 層 | agent | 処置 |
|---|---|---|
| **sonnet に変更（6）** | drift-observer / architecture-mapper / code-explorer / critic / researcher / scout | frontmatter `model: inherit` → `model: sonnet` |
| **sonnet 維持（6）** | convention-scout / market-researcher / oss-scout / pattern-observer / security-reviewer / debugger | 変更なし（テストで固定化） |
| **inherit 維持（2）** | analyst / designer | 変更なし（考える部分＝強モデル継承。テストで固定化） |
| **対象外（1）** | capabilities | spawn されない reference doc（model 行なし） |

grill 確定判断:
- **critic / scout / researcher は sonnet**: 「読んで判断を返すだけ」はコードを書かないので
  sonnet で十分（memory の分類とも一致）。
- **debugger はユーザー判断で sonnet のまま**: コスト重視。難案件はメインループ（強モデル）が
  直接デバッグする運用でカバー。
- **analyst / designer のみ inherit**: 要件の結晶化・design.md 生成は「考える部分」。

### 硬直化しない理由（旧 memory の懸念への回答）

memory は「静的書き換えは避ける（将来コードを書く用途に転用されたとき硬直化）」としていたが、
Agent ツールの明示 `model` パラメータは **frontmatter より優先される**ため、呼び出し側の
per-call override 余地は静的固定後も残る。加えて対象 agent は tools が Read/Glob/Grep（+Web）
中心でコードを書けない。同乗作業として memory 側を「構造的に read-only な agent は静的固定が正・
per-call override は可能なまま」に更新する（リポ外＝指紋非影響）。

## 機械ガード: test/agent-model-tiering.sh（新規）

FR-51 `gotcha-actor-routing.sh` と同型の grep-lib テスト（`test/grep-lib.sh` を source・
mktemp/cd 副作用なし）:

1. **層別リストの照合**: SONNET リスト 12 / INHERIT リスト 2 を定数で持ち、各
   `agents/<name>.md` の frontmatter `model:` 値を awk で抽出して期待値と assert。
2. **リスト外検知（新 agent の指定忘れ）**: `agents/*.md` を走査し、どちらのリストにも
   capabilities（対象外）にも属さないファイルがあれば fail し「このテストの層別リストに追加せよ
   （観測・レビュー専任なら SONNET / 考える部分なら INHERIT）」を指示。
3. **positive control（FR-51 前例踏襲）**: 検査ロジックを関数化し、mktemp fixture
   （誤った model 値の agent md）に対して**非ゼロで fail することを実走 assert**
   （lint が一度も fire せず self-graded 化するのを防ぐ）。
4. `test/run-all.sh` は `test/*.sh` を自動収集するため、配置のみで CI に乗る。

## Boundary（触る範囲）

- `agents/drift-observer.md` / `agents/architecture-mapper.md` / `agents/code-explorer.md` /
  `agents/critic.md` / `agents/researcher.md` / `agents/scout.md` — frontmatter `model:` の
  1 行変更 ×6。
- `test/agent-model-tiering.sh` — 新規。
- 出荷規約: README Changelog / ROADMAP（該当 epic に行を追加）/ version **v0.8.40**
  （plugin.json / marketplace.json 2 箇所 / README 冒頭）。
- リポ外の同乗（指紋非影響・clean 記録後に実施しない。実装中に済ませる）: memory
  `subagent-model-no-fable-inherit.md` の「静的書き換えは避ける」節を更新。
- 非スコープ: skills/monitor/SKILL.md への model 指示追記（frontmatter 固定で不要）、
  agents 以外（built-in Explore / simplify の cleanup agent 等リポ外 agent）、Haiku への
  さらなる格下げ（列挙のみ agent が将来できたときに再検討）。

## 後方互換・degrade

- agent frontmatter の `model` 変更は次セッション再起動から反映（skill/agent は要再起動、
  hook と違い即 live でない＝CLAUDE.md 規約）。挙動リスクは「観測者の応答品質が Fable→Sonnet に
  変わる」のみで、memory の判断どおり Sonnet 5 は観測・判断タスクに十分。
- 呼び出し側が Agent ツールの `model` パラメータで per-call override する余地は保持される。

## 完了条件（eval）

```
bash test/run-all.sh
```

exit 0。満たすべき性質:

1. `test/agent-model-tiering.sh` が SONNET 12 / INHERIT 2 の層別を assert して緑
   （drift-observer / architecture-mapper / code-explorer / critic / researcher / scout が
   `model: sonnet` に変わっている）。
2. positive control: 誤 model 値の fixture に対して検査関数が非ゼロを返すことを同テスト内で
   実走 assert。
3. リスト外の agents/*.md（capabilities 除く）が存在すると fail する（新 agent 指定忘れ検知）。
4. 既存 test 全緑（run-all 集約）。

## 検証の落とし穴（前例由来）

- frontmatter の抽出は「1 つ目の `---` と 2 つ目の `---` の間の `model:` 行」に限定する
  （本文中の `model:` 言及に誤反応しない。FR-51 の「マーカーより下だけ検査」と同じ精度設計）。
- capabilities.md は frontmatter に model 行が無い＝「リスト外検知」の除外リストに明示。
- grep-lib 系テストは chain-lib（mktemp/cd 副作用あり）を source しない（FR-42 の使い分け）。
