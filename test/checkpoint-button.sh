#!/usr/bin/env bash
# 検証: closing-checkpoint（informed stop）が prose でなく AskUserQuestion で出る指示に
# なっている（FR-41 / FR-39 phase 2）。grill / deep-interview / plan-steer の3経路すべて。
# prose ガイドなので grep（runtime smoke 対象なし）。
# C1) 3経路すべてに sentinel「残り判断の枝を選択肢に」（checkpoint をボタン化した指示）
# C2) 3経路すべてに stop オプション「握れた・進めて」
# C3) checkpoint 行（sentinel と同一行）に「AskUserQuestion」併記（prose→button の核心・design 完了条件の3つ目）
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/grep-lib.sh"   # fail/ok/$ROOT（副作用なし）
GR="$ROOT/skills/grill/SKILL.md"
DI="$ROOT/skills/deep-interview/SKILL.md"
PS="$ROOT/hooks/plan-steer.sh"

for f in "$GR" "$DI" "$PS"; do [ -f "$f" ] || fail "対象が無い: $f"; done

# ---- C1: checkpoint をボタン化した sentinel ----
for f in "$GR" "$DI" "$PS"; do
  b="$(basename "$(dirname "$f")")/$(basename "$f")"
  grep -qF "残り判断の枝を選択肢に" "$f" || fail "C1: $b に「残り判断の枝を選択肢に」（checkpoint ボタン化）が無い"
done
ok "C1) 3経路すべてに「残り判断の枝を選択肢に」"

# ---- C2: stop オプション ----
for f in "$GR" "$DI" "$PS"; do
  b="$(basename "$(dirname "$f")")/$(basename "$f")"
  grep -qF "握れた・進めて" "$f" || fail "C2: $b に stop オプション「握れた・進めて」が無い"
done
ok "C2) 3経路すべてに stop オプション「握れた・進めて」"

# ---- C3: checkpoint 指示が AskUserQuestion を sentinel と同一行に持つ（prose→button の核心）----
# ファイル全体に AskUserQuestion があるだけでは不足（grill/deep-interview/plan-steer は質問ループでも使う）。
# sentinel 行に併記されていることで「checkpoint がボタン化された」と言える。
for f in "$GR" "$DI" "$PS"; do
  b="$(basename "$(dirname "$f")")/$(basename "$f")"
  grep -F "残り判断の枝を選択肢に" "$f" | grep -qF "AskUserQuestion" \
    || fail "C3: $b の checkpoint 行に「AskUserQuestion」併記が無い（prose→button の核心が欠落）"
done
ok "C3) 3経路すべて checkpoint 行に AskUserQuestion 併記"

echo "🎉 checkpoint-button 全ケース PASS"
