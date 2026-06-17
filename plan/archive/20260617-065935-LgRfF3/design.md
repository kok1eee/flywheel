# flywheel: task 分解の型 + adopt chain — design

## 方針

2点セット。**(A) task 分解の型**: 設計成果物に「Tasks（Boundary/Depends/Done）」セクションを持たせ、
task を恣意的な数でなく**ファイル境界と依存から構造的に**割る（cc-sdd の File Structure Plan / Boundary /
Depends 由来・参考程度）。**(B) adopt chain**: 割った task を backlog に **adopt として**積み、`next` で
逐次 adopt 起動する（現状 `next` は start 固定で掘り直しが挟まる問題を解消）。A は型（主に skill/テンプレ）、
B はコード。

## File Structure Plan（task 境界の源）

- `bin/flywheel`: backlog entry に `entry` フィールド、`add --adopt`、`next` が entry を尊重、usage/list 追従
- `skills/design/SKILL.md`: design 成果物に「## Tasks（Boundary/Depends/Done）」を促す型を追記

## Tasks（cc-sdd 由来の型: Boundary / Depends / Done）

- **T1 — adopt chain（backlog の entry 化）**
  - Boundary: `bin/flywheel` の `add)` / `next)` ケース（backlog JSON に `entry`、next が `_start_goal` の第4引数へ渡す）
  - Depends: なし
  - Done(eval): mktemp で `flywheel add --adopt "x"` → `flywheel next` → `flywheel get '.entry'` == `adopt`
- **T2 — task 分解の型（design テンプレ）**
  - Boundary: `skills/design/SKILL.md`（成果物に「## Tasks（Boundary/Depends/Done）」セクションを促す記述）
  - Depends: なし（T1 と独立・並列可。境界が `skills/` と `bin/` で重ならない）
  - Done(eval): `skills/design/SKILL.md` に `Boundary` と `Depends` を含む Tasks セクションの記述がある（grep）
- **T3 — 表示追従**
  - Boundary: `bin/flywheel` の usage 行・`list)` ケース（entry を表示）
  - Depends: T1（entry フィールドが前提）
  - Done(eval): usage に `--adopt`、`flywheel list` が各 entry の start/adopt を表示

## 完了条件（eval）

各 task の Done を統合（実装後に green。型を試す段階では Tasks 分解の妥当性が主眼）。

```
bash -n bin/flywheel
grep -qE 'add .*--adopt|--adopt' bin/flywheel
grep -qE 'Boundary|Depends' skills/design/SKILL.md
```

合格 = 構文 OK・`add --adopt` 経路が存在・design テンプレに Tasks 型が入っている（T1/T2 の最小確認。
T3 と機能テストは実装フェーズで eval を厚くする）。
