#!/usr/bin/env bash
# monitor council の mode 内訳（full/targeted/lite）を flywheel status に出す（v0.8.46）。
# monitor-verdicts.csv（fw_log_monitor_verdict が monitor-set 呼出ごとに追記・既存機構）
# の6列目 mode を集計して1行表示するだけで、CSV のフォーマット/記録ロジックは変更しない。
# chain-lib.sh の隔離ハーネス（mktemp リポ・CLAUDE_PLUGIN_DATA を /tmp）で live state / 本番 CSV を汚さない。
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/chain-lib.sh"

CSV="$CLAUDE_PLUGIN_DATA/monitor-verdicts.csv"

setup_impl "true"

# C1: CSV が無い（初回・過去バージョン） → status に monitor mode 行が出ない（エラーにもならない）
[ -f "$CSV" ] && rm -f "$CSV"
out="$("$FW" status)" || fail "C1: CSV 無しで status が非ゼロ"
printf '%s' "$out" | grep -q "^monitor mode:" && fail "C1: CSV が無いのに monitor mode 行が出た"
ok "C1: CSV が無ければ monitor mode 行は出ない"

# C2: fixture CSV（full x2 / targeted x1 / lite x1 / mode 空1行）→ 集計が status に出る
mkdir -p "$CLAUDE_PLUGIN_DATA"
printf 'timestamp,verdict,level,lenses,diff_lines,mode\n' > "$CSV"
printf '2026-01-01T00:00:00Z,clean,,,0,full\n' >> "$CSV"
printf '2026-01-01T00:01:00Z,drift,implementing,observer-behavior,10,full\n' >> "$CSV"
printf '2026-01-01T00:02:00Z,drift,implementing,observer-progress,5,targeted\n' >> "$CSV"
printf '2026-01-01T00:03:00Z,clean,,,0,lite\n' >> "$CSV"
printf '2026-01-01T00:04:00Z,clean,,,3,\n' >> "$CSV"
out="$("$FW" status)" || fail "C2: fixture CSV で status が非ゼロ"
printf '%s' "$out" | grep -q "^monitor mode: full=2 targeted=1 lite=1 未記録=1（累積・全goal）$" \
  || fail "C2: monitor mode 行の集計が不一致: $(printf '%s' "$out" | grep '^monitor mode:')"
ok "C2: full/targeted/lite/未記録 の集計が status に出る"

# C3: 実際に monitor-set を呼んでも（既存機構が正しく記録し）カウントが増える
n_full_before="$(printf '%s' "$out" | grep -oE 'full=[0-9]+' | grep -oE '[0-9]+')"
"$FW" monitor-set clean >/dev/null || fail "C3: monitor-set clean が非ゼロ"
out2="$("$FW" status)" || fail "C3: monitor-set 後の status が非ゼロ"
n_full_after="$(printf '%s' "$out2" | grep -oE 'full=[0-9]+' | grep -oE '[0-9]+')"
[ "$n_full_after" -eq "$((n_full_before + 1))" ] \
  || fail "C3: monitor-set clean 後に full カウントが+1されていない（before=$n_full_before after=$n_full_after)"
ok "C3: monitor-set の実呼出が status の集計に反映される"

echo "🎉 monitor-mode-status 全ケース PASS"
