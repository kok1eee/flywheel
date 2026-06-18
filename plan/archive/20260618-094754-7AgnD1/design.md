# design: grill closing-checkpoint を AskUserQuestion 化（FR-39 phase 2）

会話で合意した方針の結晶化。FR-41（FR-39 phase 2）。

## 背景（なぜ）

FR-39 で informed-stop（止める前に「未決の判断の枝」を提示してから人間に stop/continue を聞く）を
入れたが、3経路とも **prose** で「列挙して人間に聞く」と書いた。prose はモデルが省略・埋没させられる
＝**buttonize の動機（構造的に必ず出す）を満たさない**。closing-checkpoint を **AskUserQuestion** で
出し、残り判断の枝を**選択肢**に・「握れた・進めて」を**1クリック**にする。

dogfood で本人が確認: binary（枝は質問文＝prose・選択肢は stop/continue だけ）は枝を prose に戻す＝
動機を自己矛盾。**枝そのものをボタンにする**ことでモデルの列挙が強制され、informed-stop の核心
（false-positive な握れた感を「枝の可視化」で殺す）が最も効く。

## 変更点（prose ガイドのみ・新機構ゼロ）

3経路の checkpoint 指示を「prose で列挙して聞く」→「**AskUserQuestion で出す**」に:
- `skills/grill/SKILL.md`（Step 3 + L41）/ `skills/deep-interview/SKILL.md`（L62）/ `hooks/plan-steer.sh`（L24）

仕様（Option 1・dogfood で決定）:
- options = 残り判断の枝のうち効く **上位3つ**（各 option = 1つの未決判断）+ 4つ目「**握れた・進めて**」
- **single-select**（枝を選ぶ→その枝を詰める→再 checkpoint / 「握れた・進めて」で stop）
- 残り枝が **4個超** なら質問文に「他に N 個」と添える（top-3 を出し、逐次で消化）
- 「**止めるのは人間**」は不変（FR-39）。本 phase は「どう出すか」を prose→ボタンに変えるだけ

各経路に **canonical な指示文（sentinel）** を入れて test が grep できるようにする:
`残り判断の枝を選択肢に`（上位3＋「握れた・進めて」・single-select）＋ `AskUserQuestion` 併記。

## 非スコープ

- `plan-steer.sh` は hook なので自分で AskUserQuestion を呼べない → **モデルに「checkpoint は
  AskUserQuestion で出せ」と指示する injected text** にする（呼ぶのはモデル）。
- `commands/add.md`（3点 bounded grill）/ adopt — 不変（FR-39 と同じ非スコープ）。
- completeness-critic / plan-gate 強制（FR-39 で defer 済み）。
- grep を超える eval — prose ガイドで runtime smoke 対象が無いため grep が現実的な done
  （monitor が繰り返す「grep だけは弱い」指摘は、runtime のある goal 向けで本件は非該当）。

## 完了条件（eval）

`test/checkpoint-button.sh`: grill / deep-interview / plan-steer の3経路すべてに、closing-checkpoint を
AskUserQuestion で出す指示（sentinel `残り判断の枝を選択肢に` ＋ `握れた・進めて` ＋ `AskUserQuestion`）が
存在すること。

```bash
bash test/checkpoint-button.sh
```
