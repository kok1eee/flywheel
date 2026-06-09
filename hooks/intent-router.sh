#!/usr/bin/env bash
# intent-router (UserPromptSubmit) — invisible auto-engage（opt-in）
# build 意図の強い prompt を検知して flywheel を自動 start する。「使っていることを
# 感じさせない」理想形。ただし誤爆（質問・些末修正で gate が閉じる）を避けるため:
#   - opt-in: FLYWHEEL_AUTO=1 のときだけ動く
#   - 既に active / dormant でない なら何もしない
#   - 質問・調査・説明依頼は engage しない（除外パターン）
#   - 不要なら flywheel reset / FLYWHEEL_OFF=1 で即解除
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

[[ "${FLYWHEEL_OFF:-}"  == "1" ]] && exit 0
[[ "${FLYWHEEL_AUTO:-}" == "1" ]] || exit 0   # opt-in でなければ沈黙
fw_state_exists && exit 0                       # 既に goal 進行中なら触らない

INPUT="$(cat)"
prompt="$(printf '%s' "$INPUT" | jq -r '.prompt // empty' 2>/dev/null || true)"
[[ -z "$prompt" ]] && prompt="$INPUT"           # フィールド名が違っても raw で拾う（堅牢化）

# 除外: 質問・調査・説明・些末確認は engage しない
if printf '%s' "$prompt" | grep -qiE '\?|？|教えて|とは何|どう(やって|すれば|なる)|なぜ|調べて|読んで|確認して|説明して|どこ|何が'; then
  exit 0
fi
# engage: 実装・作成・機能追加の意図（substantial な build）
if printf '%s' "$prompt" | grep -qiE '実装して|作って|作りたい|機能を?(追加|作)|新機能|新しく.{0,8}(作|追加)|build |implement|add .{0,12}feature'; then
  goal="$(printf '%s' "$prompt" | tr '\n' ' ' | head -c 200)"
  eval_cmd="$(fw_detect_eval)"
  fw_init "$goal" "$eval_cmd" "true"
  jq -cn --arg g "$goal" --arg e "${eval_cmd:-（自動検出なし。--eval 推奨）}" \
    '{hookSpecificOutput: {hookEventName: "UserPromptSubmit",
      additionalContext: ("🎯 flywheel auto-engage（FLYWHEEL_AUTO）: 設計ゲートを有効化しました。\n  goal: " + $g + "\n  eval: " + $e + "\nまず plan/requirements.md と plan/design.md を書いてください（grill で叩く）。設計が validate を通ると実装ゲートが開きます。この auto-engage が不要なら flywheel reset。")}}'
fi
exit 0
