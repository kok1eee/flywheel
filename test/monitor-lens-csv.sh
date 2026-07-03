#!/usr/bin/env bash
# lens 効果計測（FR-52）: monitor-set --lens が monitor-verdicts.csv に verdict 1行を記録することを検証。
# chain-lib.sh の隔離ハーネス（mktemp リポ・CLAUDE_PLUGIN_DATA を /tmp）で live state / 本番 CSV を汚さない。
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/chain-lib.sh"

CSV="$CLAUDE_PLUGIN_DATA/monitor-verdicts.csv"

setup_impl "true"   # chain-lib の goal 起動ヘルパ（monitor-set は fw_state_exists のみ要求）

# C1: drift + --lens → ヘッダ + drift 行（lenses はカンマ列 → | 連結）。state 側も従来どおり記録。
"$FW" monitor-set drift implementing "r1" --lens observer-behavior,observer-requirement >/dev/null \
  || fail "C1: monitor-set drift --lens が非ゼロ"
[ -f "$CSV" ] || fail "C1: CSV が作られていない"
head -1 "$CSV" | grep -q '^timestamp,verdict,level,lenses$' || fail "C1: ヘッダ不一致: $(head -1 "$CSV")"
grep -q ',drift,implementing,observer-behavior|observer-requirement$' "$CSV" \
  || fail "C1: drift 行が無い: $(cat "$CSV")"
[ "$(getf '.monitor.status')" = "drift" ] || fail "C1: state の monitor.status が drift でない"
ok "C1: drift + --lens が CSV 1行 + state 記録"

# C2: clean（--lens なし）→ level/lenses 空の行（レンズ効果の分母＝council 実行回数として記録）
"$FW" monitor-set clean >/dev/null || fail "C2: monitor-set clean が非ゼロ"
grep -q ',clean,,$' "$CSV" || fail "C2: clean 行が無い: $(cat "$CSV")"
ok "C2: clean が分母として記録される"

# C3: pending → 行が増えない（fuse の priming 等・council の verdict でない＝分母を汚さない）
n_before="$(grep -c . "$CSV")"
"$FW" monitor-set pending >/dev/null || fail "C3: monitor-set pending が非ゼロ"
[ "$(grep -c . "$CSV")" = "$n_before" ] || fail "C3: pending が CSV に記録された"
ok "C3: pending は非記録"

# C4: データ領域が書き込み不能でも verdict 記録は成功する（observation-only の実証）
rm -f "$CSV"
chmod 555 "$CLAUDE_PLUGIN_DATA"
rc=0; "$FW" monitor-set drift implementing "r2" --lens observer-progress >/dev/null 2>&1 || rc=$?
chmod 755 "$CLAUDE_PLUGIN_DATA"
[ "$rc" = "0" ] || fail "C4: CSV 書き込み不能で monitor-set が失敗した（rc=$rc）"
[ "$(getf '.monitor.reason')" = "r2" ] || fail "C4: verdict が state に入っていない"
[ ! -f "$CSV" ] || fail "C4: 書き込み不能なのに CSV ができている"
ok "C4: 計測失敗でも verdict 記録は成功（observation-only）"

# C5: drift + --lens なし → 警告を stderr に出しつつ exit 0（忘れの可視化。正当に空の clean と区別）
errout="$("$FW" monitor-set drift implementing "r3" 2>&1 >/dev/null)" || fail "C5: --lens なし drift が非ゼロ"
printf '%s' "$errout" | grep -q -- "--lens" || fail "C5: --lens 欠落の警告が出ていない: $errout"
grep -q ',drift,implementing,$' "$CSV" || fail "C5: lens 空の drift 行が記録されていない: $(cat "$CSV")"
ok "C5: --lens 忘れの drift は警告付きで記録される"

# C6: clean + --lens（余計方向）→ 警告を stderr に出しつつ exit 0（contract の両方向を機械観測）
errout="$("$FW" monitor-set clean --lens observer-behavior 2>&1 >/dev/null)" || fail "C6: clean --lens が非ゼロ"
printf '%s' "$errout" | grep -q -- "--lens" || fail "C6: clean + --lens の警告が出ていない: $errout"
ok "C6: clean への余計な --lens も警告される"

echo "🎉 monitor-lens-csv 全ケース PASS"
