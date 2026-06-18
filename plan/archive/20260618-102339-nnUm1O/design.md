# design: grill/SKILL.md:41 原則 bullet を Step3 ボタン化と整合（FR-43）

adopt（結晶化）。FR-41 の monitor が拾った非ブロック nit の整合。

## 背景（なぜ）

FR-41 で grill の Step 3 closing-checkpoint を AskUserQuestion 化したが、`skills/grill/SKILL.md:41` の
原則 bullet（informed stop の "what/why"＝止めるのは人間・判断の枝が残る限り止まらない）は
**prose 描写のまま**で、操作の "how"（AskUserQuestion）は Step 3 に集約されている。同一 skill 内で
表現が割れている（FR-41 monitor が conf72・非ブロックで指摘）。L41 に Step 3 への参照を一言足して整合。

## 変更点（微修正）

- `skills/grill/SKILL.md:41` の原則 bullet に、checkpoint の提示が **AskUserQuestion で Step 3 に集約**
  されている旨の参照（文字列「Step 3 参照」を含む）を追記。意味（止めるのは人間・informed stop）は不変、
  how の所在を指すだけ。

## 非スコープ

- Step 3 本体（FR-41 でボタン化済み）・他 skill / hook。

## 完了条件（eval）

```bash
grep -q "Step 3 参照" skills/grill/SKILL.md
```
