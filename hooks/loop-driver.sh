#!/usr/bin/env bash
# loop-driver (Stop hook) — FR-5, FR-6, FR-9, FR-11
# 継続そのものは native /goal に任せる（C-1: Stop hook の連続 cap を避ける）。
# この hook は「polish 挿入 + eval veto」に徹する:
#   implementing → polish（simplify を steer, FR-11）→ eval（ty/ruff/test の CLI 判定）→ done/implementing
#
# eval は test/build/型/lint の exit code のみで決定論判定（M-1）。挙動検証(LLM)は将来。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

fw_hook_guard || exit 0

# phase/eval_cmd/veto_count/polish を1回の jq で取得（Stop hook は毎ターン走るので fork を抑える）
# 区切りは Unit Separator(0x1F)。タブ等の whitespace は read が空フィールドを畳んでズレるため使わない。
IFS=$'\037' read -r phase eval_cmd veto polish < <(
  jq -r '[.phase // "", .eval_cmd // "", .veto_count // 0,
          (if .polish == null then true else .polish end)] | map(tostring) | join("")' "$FW_STATE"
)
# done / no-spec / designing（grill 人間待ち = FR-9 停止点b）→ stop 許可
fw_work_active "$phase" || exit 0

cap="${FLYWHEEL_VETO_CAP:-${CLAUDE_CODE_STOP_HOOK_BLOCK_CAP:-8}}"
veto="${veto:-0}"

# polish 段（FR-11）: 実装後・eval 前に1ターン simplify を steer する。
# polish=true かつ spec-ready/implementing のときだけ発火。次の停止（phase=polish）では飛ばして eval へ。
if [[ "$polish" == "true" && ( "$phase" == "spec-ready" || "$phase" == "implementing" ) ]]; then
  fw_advance polish "loop-driver: enter polish (simplify)"
  echo "🪄 flywheel: 実装が一段落。Skill: simplify でコードを整理してください（polish: reuse/簡素化/効率/altitude）。次の停止で品質チェック（${eval_cmd:-未設定}）を回します。" >&2
  exit 2
fi

# eval_cmd 未設定 → 決定論判定できない。degrade: stop を許可しつつ警告（無限ブロックを避ける）。
if [[ -z "$eval_cmd" ]]; then
  echo "⚠️ flywheel: eval_cmd 未設定のため done を機械判定できません。'flywheel start --eval \"<ty/ruff/test>\"' で設定すると loop が完了を強制します。今回は stop を許可します。" >&2
  exit 0
fi

# eval phase へ進め、ty/ruff/test を CLI 実行（決定論）
[[ "$phase" != "eval" ]] && fw_advance eval "loop-driver: enter eval"
out="$(cd "$FW_ROOT" && bash -c "$eval_cmd" 2>&1)" && rc=0 || rc=$?

if [[ "$rc" -eq 0 ]]; then
  fw_set_num veto_count 0
  fw_advance done "loop-driver: eval pass ($eval_cmd)"
  arch="$(fw_archive_plan)"   # FR-12: 完了スペックを退避（plan/ をクリーンに）
  echo "✅ flywheel: eval 合格（$eval_cmd）。goal 達成として done。" >&2
  [[ -n "$arch" ]] && echo "   設計を退避: ${arch#"$FW_ROOT"/}" >&2
  n="$(fw_backlog_count)"
  [[ "$n" -gt 0 ]] && echo "📋 backlog に $n 件。'flywheel next' で次を開始してください。" >&2
  exit 0   # stop 許可
fi

# 失敗 → veto。cap 到達なら人間に返す（FR-10）、未満なら implementing に戻して継続強制。
veto=$((veto + 1))
fw_set_num veto_count "$veto"
if [[ "$veto" -ge "$cap" ]]; then
  fw_advance implementing "loop-driver: veto cap $cap 到達 — 人間介入が必要"
  echo "🛑 flywheel: eval が $cap 回失敗（$eval_cmd）。自動修正の上限に達したので人間に返します。最新の失敗:
$(printf '%s' "$out" | tail -15)" >&2
  exit 0   # cap 到達 → stop 許可（人間判断へ）
fi

fw_advance implementing "loop-driver: eval fail, veto $veto/$cap"
cat >&2 <<EOF
🔁 flywheel: eval 未達（$eval_cmd, veto $veto/$cap）。done にできません。修正して続けてください。
goal: $(fw_get '.goal')
失敗内容:
$(printf '%s' "$out" | tail -15)
EOF
exit 2   # stop を拒否 → 継続強制
