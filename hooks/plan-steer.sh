#!/usr/bin/env bash
# plan-steer (UserPromptSubmit) — FR-24
# engage 中（FLYWHEEL_PLAN=1）の plan mode で、grill の操作系（圧縮版）を毎プロンプト注入し
# **既定動作**にする。「/flywheel:grill を使え」という prose 誘導（= flywheel が殺そうとした形）を
# やめ、skill 発動に依存しない。毎プロンプト注入なので compaction 後も効く（FR-17 と同じ思想）。
# 明示的 /flywheel:grill はオンデマンド深掘り・CLI route 用に残る。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

[[ "${FLYWHEEL_OFF:-}"  == "1" ]] && exit 0
[[ "${FLYWHEEL_PLAN:-}" == "1" ]] || exit 0   # FR-23: opt-in

INPUT="$(cat)"
mode="$(printf '%s' "$INPUT" | jq -r '.permission_mode // empty' 2>/dev/null || true)"
[[ "$mode" == "plan" ]] || exit 0

jq -cn '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext:
"🛞 flywheel plan-mode（grill 既定動作・FR-24）— この計画作りでは以下を守ること:
- 計画の決定点を列挙する。self-answer してよいのは *事実*（実装・既存パターン・コードに答えがある）だけ — Glob/Grep/Read で埋める
- *判断*（スコープ/トレードオフ/優先順位/命名/どの案か）はコードに答えが無い → 必ず AskUserQuestion で1問ずつ・推奨案と理由を添えて聞く。迷ったら聞く側に倒す（self-answer で済ませない＝質問しない計画は失敗）
- 計画には「## 非スコープ」と「## 完了条件（eval）」を必ず含める。完了条件は done を機械判定する fenced bash block（1行 = 1コマンド、&& 連結で実行される）
- モデルは「詰め切った」を自己判定しない——**止めるのは人間**。ExitPlanMode の前に、まだ決めていない **未決の判断** の枝（スコープ/トレードオフ/命名/案の選択）を提示し、止めるか続けるかは人間が決める。形式不足の計画は plan-gate が差し戻す
承認されると flywheel が計画を plan/design.md に保存し、完了条件を eval として done まで自動 loop します。"}}'
exit 0
