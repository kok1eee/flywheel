#!/usr/bin/env bash
# session-greeter (SessionStart) — FR-17
# セッション開始時（startup / resume / compaction 復帰）に flywheel の現況を context に注入する。
#
# dormant: 入口案内（v0.4.1）。「最初は start を使え」を強制でなく示唆で伝える。
#   - gate を閉じない（state を作らない。思い出させるだけ）
#
# active: 再アンカー（v0.4.3）。state.json は context 非依存（FR-7）だが、モデルの context は
#   compaction / セッション切替で消える。phase / goal / 次にすべきことを再注入して
#   数時間〜数日の長時間自律運転を支える（Fable 5 の長時間 context 保持を harness 側から補強）。
#
# FLYWHEEL_OFF=1 なら常に沈黙。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

[[ "${FLYWHEEL_OFF:-}" == "1" ]] && exit 0

emit() {  # $1 = additionalContext
  jq -cn --arg c "$1" '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $c}}'
  exit 0
}

# --- active: 再アンカー ---
if fw_state_exists; then
  phase="$(fw_phase)"
  case "$phase" in
    no-spec|designing)
      next="$(fw_designing_steer)" ;;
    spec-ready)
      next="→ 設計は合格済み・実装ゲートは開いています。実装を開始してください（最初の source 編集で implementing へ）。" ;;
    implementing|polish|eval)
      next="→ 実装を続けてください。停止すると loop-driver が eval（$(fw_get '.eval_cmd')）で done を判定します。" ;;
    done)
      next="→ goal は達成済み。次へ: $FW_CLI next（backlog から次を起動）/ $FW_CLI reset（dormant に戻す）" ;;
    *)
      next="" ;;
  esac
  emit "🛞 flywheel 稼働中: phase=$phase
  goal: $(fw_get '.goal')
$next
  状態: $FW_CLI status / 中止: $FW_CLI reset / bypass: FLYWHEEL_OFF=1"
fi

# --- dormant: 入口案内 ---
if [[ "${FLYWHEEL_PLAN:-}" == "1" ]]; then
  plan_line="plan route: ON（Shift+Tab で plan mode に入ると grill 既定動作 + 承認で自動 loop）"
else
  plan_line="plan route: off（export FLYWHEEL_PLAN=1 で「plan mode = flywheel」になる）"
fi
emit "🛞 flywheel は dormant（設計ゲートは開いており通常作業の邪魔はしません）。
  しっかり作るなら: Shift+Tab で plan mode / 明示起動: /flywheel:start <作りたいこと> / $FW_CLI start \"<作りたいこと>\"
  ${plan_line}
  迷ったら /flywheel:guide（使い方・ルート選択・詰まりの地図）"
