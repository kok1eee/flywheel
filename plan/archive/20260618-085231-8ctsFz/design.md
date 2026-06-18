# design: grill 終了判定の lever-1 化（self-graded stop の撤去）

会話で合意した方針の結晶化（adopt・掘り直し無し）。FR-39。

## 背景（なぜ）

詰問（grill / deep-interview / plan route）の「もう十分」を、**収束したがるモデル側が自己判定**している
＝ self-graded termination。3経路すべて該当:

- `skills/deep-interview/SKILL.md:26,62,84` — 「最大 7問 で打ち切る（ユーザーの負担を最小化）」という
  ハードキャップ。under-ask を生む前提がベタ書き。
- `skills/grill/SKILL.md:41` — 「共有理解に達するまで…ただし『もういい/十分』で打ち切る」＝モデルが
  共有理解到達を自己判定。
- `hooks/plan-steer.sh:24` — 「詰め切るまで ExitPlanMode しない」＝モデルが「詰め切った」を自己判定。
  後段 `plan-gate.sh` は形式（非スコープ＋完了条件＋fenced block）しか見ず判断の数を見ない。

問題: ユーザーの「握れた感」は false-positive（その時は握れた気がするが、後で「もっと聞いてほしかった」
と気づく）。要件は実装の具体に殴られて発掘されるため、grill 時点での「もう十分」は早すぎる。

**安全性の根拠**: done の self-graded ゲートが危険なのは人間 *不在* 時（無人 loop / done）に発火するから。
grill の終了は人間が *live で会話にいる* 最中に起きる。よって「残り枝を見せて人間が止める」を prose で
書けばその場で non-compliance を捕まえられる＝重い hook 機構は不要。**prose のみで実装する。**

## 変更点（prose のみ・新機構ゼロ）

共通の value 反転 + 機構（lever 1）:
1. 「負担最小化で早く止める」前提を撤去。under-ask が失敗・聞かれるのは歓迎、と反転。
2. モデルは「もう十分」を自己宣言しない。default は *判断* の枝を出し続ける。**止めるのは人間**
   （もういい / 握れた / 進めて）。
3. 止める直前に「まだ決めてない **未決の判断** の枝はこれ」を1回提示してから人間に stop/continue を聞く
   （informed stop＝closing checkpoint を1個追加。途中の摩擦は増やさない）。

**lever 1 ≠ 無限に聞く**: `事実=self-answer` filter（`grill/SKILL.md:40-41`）は維持。判断の枝が残る間だけ
止まらない＝低価値質問を量産しない（質を上げるだけ）。

ファイル別:
- `skills/deep-interview/SKILL.md` — `最大 7問` ハードキャップを撤去（残った曖昧軸を提示して
  「続ける? 進める?」の continue チェックポイントに変える）。L26 原則 / L62 ループ終了条件 / L84 Gotcha。
- `skills/grill/SKILL.md:41` — 「共有理解に達するまで…打ち切る」を「判断の枝が残る限り止まらない・
  止めるのは人間・止める前に未決の判断の枝を提示」に。Step 3 にも closing checkpoint を明記。
- `hooks/plan-steer.sh:24` — 「ExitPlanMode の前に未決の判断の枝を提示し、止めるのは人間」を追加。
  モデルは「詰め切った」を自己宣言しない。

AI 向けガイドなので **説明は厚く・ただし要のルールを際立たせる**（埋もれると compliance 低下）。

各ファイルに canonical な sentinel 文言を入れて test が grep できるようにする:
- 「**止めるのは人間**」（human owns stop）
- 「**未決の判断**（の枝）」（surface remaining before stop）

## 非スコープ

- `commands/add.md`（3点軽量 grill）/ adopt — 意図的に bounded なので不変。
- `hooks/plan-gate.sh` — 形式ゲートのまま（判断完全性は live 人間＋上記 prose が担う）。
- completeness-critic（独立 agent で残り枝を列挙）— 今回入れない。人間 live で足りるか dogfood し、
  まだ under-surface するなら次 phase。
- `flywheel:adopt` の args sanitize 不足（`!` 行が長い/特殊文字 args で parse error）— 別途 ROADMAP。

## 完了条件（eval）

prose 変更なので flywheel-native の grep レベル test を `test/grill-termination.sh` に追加し、それを回す:
- deep-interview から `7問` ハードキャップが消えていること
- grill / deep-interview / plan-steer に「止めるのは人間」「未決の判断」の新ルール文言が存在すること
- grill の `事実=self-answer` filter が温存されていること（lever 1 が「無限に聞く」に退行していない回帰ガード）

```bash
bash test/grill-termination.sh
```
