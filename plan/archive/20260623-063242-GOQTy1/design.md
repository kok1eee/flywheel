# design: greeter に /flywheel:guide 導線を足す（FR-47）

adopt（結晶化）。session-greeter は entry point（plan mode / `/flywheel:start`）は出すが「**使い方を学ぶ**
入口」を出していない。Claude が flywheel の駆動に迷ったとき `/flywheel:guide`（ルート選択・どの skill・
詰まりの地図）へ辿れる導線を dormant 案内に1行足す。

## 背景・判断（grill 済み）

- **狙い**: greeter は SessionStart hook で **Claude の context に injection** される＝Claude が毎セッション
  見る。そこに guide 導線を置けば「使い方が分からず素手で大物を作り始める」を入口で減らせる。
- **A だけ**（greeter のみ）に倒す判断: B（global CLAUDE.md への常設 pointer）は全リポで発火・config と
  plugin を結合・auto-engage（削除した intent-router）に倒れやすい。greeter は plugin 所有で自己記述的・
  判断タイミング（タスク開始＝SessionStart）と合う。A で不足が実証されたら B を後で足す（投機しない）。
- **`/flywheel:guide` を指す**（生 SKILL.md 直読みでない）: guide はその用途の決定ガイド skill。
- **dormant のみ**: 「使うか・どう使うか」の判断は dormant 時に起きる。active（稼働中）は status/reset と
  phase 別 next が既にあるので対象外（最小スコープ）。

## 変更点

### 1. `hooks/session-greeter.sh` — dormant emit に1行

dormant 案内の emit（`${plan_line}` の次）に導線を追加:

```
  迷ったら /flywheel:guide（使い方・ルート選択・詰まりの地図）
```

### 2. `test/greeter-guide.sh`（新規・grep ガード）

session-greeter.sh が `/flywheel:guide` を案内していることを assert（再混入ならぬ「導線の消失」回帰を
CI で防ぐ）。grep-only なので副作用なしの `grep-lib.sh` を source。

### 3. docs / version

version v0.8.27（plugin.json + marketplace.json 2箇所 + README 冒頭 + Changelog）。ROADMAP に FR-47 を
✅ 実装済で計上。

## 非スコープ

- **B（global CLAUDE.md への pointer）**: A で不足が実証されてから（投機しない）。
- active（稼働中）greeter・他 hook・guide skill 本体は不変。

## 完了条件（eval）

```bash
bash test/run-all.sh
```
