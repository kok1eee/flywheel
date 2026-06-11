#!/usr/bin/env bash
# loop-driver (Stop hook) — FR-5, FR-6, FR-9, FR-11
# 継続そのものは native /goal に任せる（C-1: Stop hook の連続 cap を避ける）。
# この hook は「eval veto + polish 挿入」に徹する:
#   implementing → eval（ty/ruff/test の CLI 判定）→ 初回合格で polish（simplify を steer, FR-11）
#   → 再 eval → done。未達なら implementing に戻して veto。
#
# polish は「初回 eval 合格後」に goal につき1回だけ（v0.4.2 / polish-on-green）:
#   修正ループに polish が挟まらず（turn 最短）、磨く対象は修正込みの最終形、
#   green 起点なので polish 後の再 eval 失敗は simplify が犯人と確定できる。
# eval は test/build/型/lint の exit code のみで決定論判定（M-1）。挙動検証(LLM)は将来。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

fw_hook_guard || exit 0

# phase/eval_cmd/veto_count/polish/polished を1回の jq で取得（Stop hook は毎ターン走るので fork を抑える）
# 区切りは Unit Separator(0x1F)。タブ等の whitespace は read が空フィールドを畳んでズレるため使わない。
IFS=$'\037' read -r phase eval_cmd veto polish polished < <(
  jq -r '[.phase // "", .eval_cmd // "", .veto_count // 0,
          (if .polish == null then true else .polish end),
          (.polished // false)] | map(tostring) | join("\u001f")' "$FW_STATE"
)
# done / no-spec / designing（grill 人間待ち = FR-9 停止点b）→ stop 許可
fw_work_active "$phase" || exit 0

cap="${FLYWHEEL_VETO_CAP:-${CLAUDE_CODE_STOP_HOOK_BLOCK_CAP:-8}}"
veto="${veto:-0}"

# veto を1加算し、cap 到達なら理由付きで stop を許可して人間に返す（FR-10）。
# 使い方: bump_veto_or_handoff "<cap 到達時のメッセージ>" && exit 0（cap 到達時のみ 0 を返す）
bump_veto_or_handoff() {
  veto=$((veto + 1))
  fw_set_json veto_count "$veto"
  if [[ "$veto" -ge "$cap" ]]; then
    fw_advance implementing "loop-driver: veto cap $cap 到達 — 人間介入が必要"
    echo "🛑 flywheel: veto が $cap 回に達したので人間に返します。$1" >&2
    return 0
  fi
  return 1
}

# polish 段に入る（FR-11・polished フラグで goal につき1回だけ）。
enter_polish() {  # $1 = steer メッセージの冒頭文脈
  fw_set_json polished true
  fw_advance polish "loop-driver: enter polish (simplify)"
  fw_log_usage "steer:simplify"   # FR-18: steer 従命率の分母
  echo "$1 Skill: simplify でコードを整理してください（polish: reuse/簡素化/効率/altitude）。次の停止で再度品質チェックし、通れば done です。" >&2
  exit 2
}

# polish を実施すべきか（FR-11 + FR-20 の diff 適応）。
# polish=true・未実施で、goal の累積 diff が閾値以上のときだけ 0 を返す。
# 小 diff の goal（typo 修正等）は simplify 1ターンが過剰なので skip して即 done へ。
should_polish() {
  [[ "$polish" == "true" && "$polished" != "true" ]] || return 1
  local min="${FLYWHEEL_POLISH_MIN_DIFF:-30}" n
  n="$(fw_goal_diff_lines)"
  if [[ -n "$n" && "$n" -lt "$min" ]]; then
    fw_set_json polished true   # skip も実施判断済みとして記録（再判定しない）
    echo "ℹ️ flywheel: goal の累積 diff が ${n} 行（閾値 ${min} 未満・FLYWHEEL_POLISH_MIN_DIFF）のため polish を省略します。" >&2
    return 1
  fi
  return 0   # diff が大きい or 計測不能（baseline なし）→ 従来どおり polish
}

# spec-ready のまま停止 = 門が開いたのに source 編集ゼロ。eval を回すと「未実装でも既存
# テストは green」で空振り done になり得るため、回さず実装開始を steer する（veto で cap 保護）。
# 既知の縁: Bash だけで完結する goal はここに留まる（H-1 と同根）→ FLYWHEEL_OFF=1 で逃がす。
if [[ "$phase" == "spec-ready" ]]; then
  bump_veto_or_handoff "実装が開始されていません（Bash のみで完結する goal なら FLYWHEEL_OFF=1）。" && exit 0
  echo "▶️ flywheel: 設計は合格済み（spec-ready）ですが実装がまだです。実装を開始してください。goal: $(fw_get '.goal')" >&2
  exit 2
fi

# eval_cmd 未設定 → 決定論判定できない。polish だけ1回挿入し、stop は許可（無限ブロックを避ける）。
if [[ -z "$eval_cmd" ]]; then
  should_polish && enter_polish "🪄 flywheel: 実装が一段落。"
  echo "⚠️ flywheel: eval_cmd 未設定のため done を機械判定できません。'flywheel start --eval \"<ty/ruff/test>\"' で設定すると loop が完了を強制します。今回は stop を許可します。" >&2
  exit 0
fi

# eval phase へ進め、ty/ruff/test を CLI 実行（決定論）。
# - mise shims を PATH に前置: hook の非対話環境で npm/node 等が見えず eval が常に fail する事故を防ぐ
# - timeout で hook timeout(600s) より先に自前で打ち切り、silent kill（判定なしで stop が通る）を明示の veto に変換
prev_phase="$phase"
[[ "$phase" != "eval" ]] && fw_advance eval "loop-driver: enter eval"
[[ -d "$HOME/.local/share/mise/shims" ]] && export PATH="$HOME/.local/share/mise/shims:$PATH"
eval_timeout="${FLYWHEEL_EVAL_TIMEOUT:-540}"
out="$(cd "$FW_ROOT" && timeout "$eval_timeout" bash -c "$eval_cmd" 2>&1)" && rc=0 || rc=$?
[[ "$rc" -eq 124 ]] && out="⏱ eval が ${eval_timeout}s でタイムアウト。eval_cmd を軽くするか FLYWHEEL_EVAL_TIMEOUT を上げてください。
$out"

if [[ "$rc" -eq 0 ]]; then
  fw_set_json veto_count 0
  # 初回合格 → done の前に polish を1回（green を確認してから磨く = polish-on-green）
  should_polish && enter_polish "✅ flywheel: eval 合格（$eval_cmd）。done の前に仕上げ:"
  fw_advance done "loop-driver: eval pass ($eval_cmd)"
  arch="$(fw_archive_plan)"   # FR-12: 完了スペックを退避（plan/ をクリーンに）
  echo "✅ flywheel: eval 合格（$eval_cmd）。goal 達成として done。" >&2
  echo "   挙動エビデンスも残すなら: Skill: flywheel:verification（eval は静的判定のみ。実際に動かした証拠は別）" >&2
  fw_log_usage "steer:verification"   # FR-18: steer 従命率の分母
  [[ -n "$arch" ]] && echo "   設計を退避: ${arch#"$FW_ROOT"/}" >&2
  n="$(fw_backlog_count)"
  [[ "$n" -gt 0 ]] && echo "📋 backlog に $n 件。'flywheel next' で次を開始してください。" >&2
  exit 0   # stop 許可
fi

# 失敗 → veto。cap 到達なら人間に返す（FR-10）、未満なら implementing に戻して継続強制。
if bump_veto_or_handoff "eval が通りません（$eval_cmd）。最新の失敗:
$(printf '%s' "$out" | tail -15)"; then
  exit 0   # cap 到達 → stop 許可（人間判断へ）
fi

hint=""
[[ "$prev_phase" == "polish" ]] && hint=" 直前が polish なので simplify の変更が壊した可能性が高い — その差分を疑ってください。"
fw_advance implementing "loop-driver: eval fail, veto $veto/$cap"
cat >&2 <<EOF
🔁 flywheel: eval 未達（$eval_cmd, veto $veto/$cap）。done にできません。修正して続けてください。$hint
goal: $(fw_get '.goal')
失敗内容:
$(printf '%s' "$out" | tail -15)
EOF
exit 2   # stop を拒否 → 継続強制
