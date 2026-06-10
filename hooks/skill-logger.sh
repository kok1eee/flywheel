#!/usr/bin/env bash
# skill-logger (PreToolUse, matcher: Skill) — FR-18
# 全 Skill 使用を skill-usage.csv に記録する（観測のみ・block しない・常に exit 0）。
# flywheel が dormant でも動く（計測はリポ・goal 横断のため fw_hook_guard は使わない）。
#
# 用途（Anthropic skills blog の practice「スキルの計測」）:
#   - evolve の入力: 「最近使われたスキル」— 従来この CSV の書き手が無く、evolve は常に空データで動いていた
#   - steer 従命率: design-gate / loop-driver が記録する steer:* 行と突合して
#     「steer 発行数に対し実際に skill が撃たれた率」を出す（design.md の dogfood 宿題）
#   - 人気 / 過少トリガー skill の把握
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

[[ "${FLYWHEEL_OFF:-}" == "1" ]] && exit 0

skill="$(jq -r '.tool_input.skill // empty' 2>/dev/null || true)"
[[ -n "$skill" ]] && fw_log_usage "$skill"
exit 0
