#!/usr/bin/env bash
# session-greeter (SessionStart) — FR-17
# dormant のとき（state なし＝門が開いている）だけ、flywheel の入口を1行案内する。
# 「最初は start を使え」を強制でなく示唆で伝える、最も低摩擦・低リスクな入口層:
#   - gate を閉じない（FR-15 intent-router と違い state を作らない。思い出させるだけ）
#   - goal 進行中（state あり）なら沈黙 — 走っている loop の邪魔をしない
#   - FLYWHEEL_OFF=1 なら沈黙
#   - FLYWHEEL_AUTO の状態を併記し、常用するなら auto-engage（FR-15）を勧める
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

[[ "${FLYWHEEL_OFF:-}" == "1" ]] && exit 0
fw_state_exists && exit 0   # dormant のときだけ案内（active 中は loop 系が喋る）

if [[ "${FLYWHEEL_AUTO:-}" == "1" ]]; then
  auto_line="auto-engage: ON（FLYWHEEL_AUTO=1。「〜を実装して/作って」で自動起動、質問・調査はスルー）"
else
  auto_line="auto-engage: off（常用するなら export FLYWHEEL_AUTO=1 で build 意図を自動起動）"
fi

msg="🛞 flywheel は dormant（設計ゲートは開いており通常作業の邪魔はしません）。
  設計駆動で何か作るなら: flywheel start \"<作りたいこと>\"  /  /flywheel:start <作りたいこと>
  ${auto_line}"

jq -cn --arg c "$msg" \
  '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $c}}'
exit 0
