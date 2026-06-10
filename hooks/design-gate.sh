#!/usr/bin/env bash
# design-gate (PreToolUse, matcher: Edit|Write|NotebookEdit) — FR-1
# 設計が validate を通る前は、source への実装書き込みを物理ブロックする。
# spec-ready で最初の source 編集が通った瞬間 implementing へ遷移させる（phase-advancer の一部）。
#
# v1: Bash は block しない（H-1: pytest と調査スクリプトを正規表現で安定区別できない）。
#     block 対象は Edit/Write/NotebookEdit→source のみ。plan/ .flywheel/ docs/ *.md は常に許可。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

fw_hook_guard || exit 0   # bypass / dormant なら門は開いている

INPUT="$(cat)"
fw_parse_tool_input "$INPUT"   # → FW_TOOL / FW_FP
phase="$(fw_phase)"

# source への実装書き込みか（Edit/Write/NotebookEdit かつ非設計ファイル）
impl_write() { [[ "$FW_TOOL" == "Edit" || "$FW_TOOL" == "Write" || "$FW_TOOL" == "NotebookEdit" ]] && fw_is_impl_write "$FW_FP"; }

if fw_gate_closed "$phase"; then
  # 設計フェーズ。source への実装書き込みだけブロックする。
  if impl_write; then
    {
      echo "🚫 flywheel: 設計フェーズ未完了のため実装をブロックしました（phase=$phase）。"
      echo ""
      echo "  対象: $FW_FP"
      echo "  goal: $(fw_get '.goal')"
      echo ""
      fw_designing_steer   # artifact に応じて deep-interview/discovery-council/design/grill を案内
      echo ""
      echo "bypass: FLYWHEEL_OFF=1 / 中止: flywheel reset"
    } >&2
    exit 2
  fi
  exit 0  # plan/ への書き込み・調査等は許可
fi

# 門は開いている。spec-ready で最初の source 編集が通ったら implementing へ進める。
if [[ "$phase" == "spec-ready" ]] && impl_write; then
  fw_advance implementing "design-gate: first source edit"
fi
exit 0
