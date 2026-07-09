#!/usr/bin/env bash
# lens 効果計測（FR-52）: monitor-set --lens が monitor-verdicts.csv に verdict 1行を記録することを検証。
# + FR-56: with_readonly の復元保証（C9）。
# + v0.8.42: diff_lines 列 + mode 列（6列化・lite/標的/full council の捕捉率比較用）
#   + 旧4列/5列ヘッダからの移行（C0）+ --mode 記録（C10）。
# chain-lib.sh の隔離ハーネス（mktemp リポ・CLAUDE_PLUGIN_DATA を /tmp）で live state / 本番 CSV を汚さない。
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/chain-lib.sh"

CSV="$CLAUDE_PLUGIN_DATA/monitor-verdicts.csv"

setup_impl "true"   # chain-lib の goal 起動ヘルパ（monitor-set は fw_state_exists のみ要求）

# C0: 旧ヘッダ（4列・v0.8.33〜v0.8.41 / 5列・v0.8.42開発中）からの移行。データ行は不変・ヘッダだけ
# 6列へ書き換わり、新規行は6列で追記される（他ケースの前に、CSV がまだ存在しない状態で検証）。
mkdir -p "$CLAUDE_PLUGIN_DATA"
printf 'timestamp,verdict,level,lenses\n2026-01-01T00:00:00Z,clean,,\n' > "$CSV"
"$FW" monitor-set clean >/dev/null || fail "C0: 旧ヘッダ(4列) CSV への monitor-set が非ゼロ"
head -1 "$CSV" | grep -q '^timestamp,verdict,level,lenses,diff_lines,mode$' \
  || fail "C0: ヘッダが6列へ移行していない: $(head -1 "$CSV")"
sed -n 2p "$CSV" | grep -q '^2026-01-01T00:00:00Z,clean,,$' \
  || fail "C0: 旧データ行が書き換わっている（不変のはず）: $(sed -n 2p "$CSV")"
sed -n 3p "$CSV" | grep -q ',clean,,,0,full$' \
  || fail "C0: 新規行が6列で追記されていない: $(sed -n 3p "$CSV")"
ok "C0: 旧4列ヘッダは新規記録時に6列へ移行・既存データ行は不変"
rm -f "$CSV"
printf 'timestamp,verdict,level,lenses,diff_lines\n2026-01-01T00:00:00Z,clean,,,5\n' > "$CSV"
"$FW" monitor-set clean >/dev/null || fail "C0b: 旧ヘッダ(5列) CSV への monitor-set が非ゼロ"
head -1 "$CSV" | grep -q '^timestamp,verdict,level,lenses,diff_lines,mode$' \
  || fail "C0b: 5列ヘッダが6列へ移行していない: $(head -1 "$CSV")"
sed -n 2p "$CSV" | grep -q '^2026-01-01T00:00:00Z,clean,,,5$' \
  || fail "C0b: 旧データ行(5列)が書き換わっている（不変のはず）: $(sed -n 2p "$CSV")"
ok "C0b: 開発中5列ヘッダも新規記録時に6列へ移行・既存データ行は不変"
rm -f "$CSV"   # 以降のケースは新規 CSV から検証する

# C1: drift + --lens → ヘッダ + drift 行（lenses はカンマ列 → | 連結）。state 側にも lens が保存される。
"$FW" monitor-set drift implementing "r1" --lens observer-behavior,observer-requirement >/dev/null \
  || fail "C1: monitor-set drift --lens が非ゼロ"
[ -f "$CSV" ] || fail "C1: CSV が作られていない"
head -1 "$CSV" | grep -q '^timestamp,verdict,level,lenses,diff_lines,mode$' || fail "C1: ヘッダ不一致: $(head -1 "$CSV")"
grep -q ',drift,implementing,observer-behavior|observer-requirement,0,full$' "$CSV" \
  || fail "C1: drift 行が無い（diff_lines=0 想定・本テストは無変更、mode 省略時は full）: $(cat "$CSV")"
[ "$(getf '.monitor.status')" = "drift" ] || fail "C1: state の monitor.status が drift でない"
[ "$(getf '.monitor.lens')" = "observer-behavior|observer-requirement" ] \
  || fail "C1: state の monitor.lens が正規化済みで保存されていない（v0.8.42・標的再council の前提）"
[ "$(getf '.monitor.mode')" = "full" ] || fail "C1: state の monitor.mode が既定 full になっていない"
# C1b: timestamp 列の形式（先頭データ行が ISO8601 UTC で始まる。ヘッダ名一致だけでは値が空でも緑のため）
sed -n 2p "$CSV" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z,' \
  || fail "C1b: timestamp 列が ISO8601 UTC でない: $(sed -n 2p "$CSV")"
ok "C1: drift + --lens が CSV 1行 + state 記録（C1b: timestamp 形式込み・lens/mode は state にも保存）"

# C2: clean（--lens なし）→ level/lenses 空の行（レンズ効果の分母＝council 実行回数として記録）
"$FW" monitor-set clean >/dev/null || fail "C2: monitor-set clean が非ゼロ"
grep -q ',clean,,,0,full$' "$CSV" || fail "C2: clean 行が無い: $(cat "$CSV")"
ok "C2: clean が分母として記録される"

# C3: pending → 行が増えない（fuse の priming 等・council の verdict でない＝分母を汚さない）
n_before="$(grep -c . "$CSV")"
"$FW" monitor-set pending >/dev/null || fail "C3: monitor-set pending が非ゼロ"
[ "$(grep -c . "$CSV")" = "$n_before" ] || fail "C3: pending が CSV に記録された"
ok "C3: pending は非記録"

# C4: データ領域が書き込み不能でも verdict 記録は成功する（observation-only の実証）
rm -f "$CSV"
rc=0; with_readonly "$CLAUDE_PLUGIN_DATA" 555 "$FW" monitor-set drift implementing "r2" --lens observer-progress >/dev/null 2>&1 || rc=$?
[ "$rc" = "0" ] || fail "C4: CSV 書き込み不能で monitor-set が失敗した（rc=$rc）"
[ "$(getf '.monitor.reason')" = "r2" ] || fail "C4: verdict が state に入っていない"
[ ! -f "$CSV" ] || fail "C4: 書き込み不能なのに CSV ができている"
ok "C4: 計測失敗でも verdict 記録は成功（observation-only）"

# C5: drift + --lens なし → 警告を stderr に出しつつ exit 0（忘れの可視化。正当に空の clean と区別）
errout="$("$FW" monitor-set drift implementing "r3" 2>&1 >/dev/null)" || fail "C5: --lens なし drift が非ゼロ"
printf '%s' "$errout" | grep -q -- "--lens" || fail "C5: --lens 欠落の警告が出ていない: $errout"
grep -q ',drift,implementing,,0,full$' "$CSV" || fail "C5: lens 空の drift 行が記録されていない: $(cat "$CSV")"
ok "C5: --lens 忘れの drift は警告付きで記録される"

# C6: clean + --lens（余計方向）→ 警告を stderr に出しつつ exit 0（contract の両方向を機械観測）
errout="$("$FW" monitor-set clean --lens observer-behavior 2>&1 >/dev/null)" || fail "C6: clean --lens が非ゼロ"
printf '%s' "$errout" | grep -q -- "--lens" || fail "C6: clean + --lens の警告が出ていない: $errout"
ok "C6: clean への余計な --lens も警告される"

# C7: sanitize 経路の演習（引用符除去 + カンマ→パイプ。design の sanitize 方針で唯一未演習だった経路）
"$FW" monitor-set drift implementing "r4" --lens 'observer-a"b,observer-c' >/dev/null 2>&1 \
  || fail "C7: 引用符入り --lens で monitor-set が非ゼロ"
grep -q ',drift,implementing,observer-ab|observer-c,0,full$' "$CSV" \
  || fail "C7: sanitize（\" 除去・, → |）されていない: $(tail -1 "$CSV")"
ok "C7: lens の sanitize（引用符除去・カンマ→パイプ）が効く"

# C8: 既存 CSV への append 失敗（C4 は新規作成失敗のみ）。CSV 自体を read-only にしても verdict は成功
n_before="$(grep -c . "$CSV")"
rc=0; with_readonly "$CSV" 444 "$FW" monitor-set drift implementing "r5" --lens observer-a >/dev/null 2>&1 || rc=$?
[ "$rc" = "0" ] || fail "C8: append 失敗で monitor-set が非ゼロ（rc=$rc）"
[ "$(getf '.monitor.reason')" = "r5" ] || fail "C8: verdict が state に入っていない"
[ "$(grep -c . "$CSV")" = "$n_before" ] || fail "C8: read-only CSV に行が増えている"
ok "C8: 既存 CSV への append 失敗でも verdict 記録は成功（observation-only）"

# C9: with_readonly の復元保証 — 非ゼロ cmd でも rc が透過し、呼ぶ前の mode に復元される（FR-56）
mode_before="$(stat -c %a "$CSV")"   # umask 依存の決め打ちを避け、契約「呼ぶ前の mode に戻す」を直接検証
rc=0; with_readonly "$CSV" 444 false || rc=$?
[ "$rc" = "1" ] || fail "C9: 非ゼロ cmd の rc が透過しない（rc=$rc）"
[ "$(stat -c %a "$CSV")" = "$mode_before" ] || fail "C9: 非ゼロ cmd 後に mode が復元されていない（$(stat -c %a "$CSV") != $mode_before）"
ok "C9: with_readonly は非ゼロでも mode 復元 + rc 透過"

# C10: --mode（v0.8.42）が state + CSV に記録される。不正な値は拒否。
"$FW" monitor-set clean --mode lite >/dev/null || fail "C10: --mode lite で monitor-set が非ゼロ"
[ "$(getf '.monitor.mode')" = "lite" ] || fail "C10: state の monitor.mode が lite になっていない"
grep -q ',clean,,,0,lite$' "$CSV" || fail "C10: --mode lite が CSV に記録されていない: $(tail -1 "$CSV")"
"$FW" monitor-set drift implementing "r6" --lens observer-progress --mode targeted >/dev/null \
  || fail "C10: --mode targeted で monitor-set が非ゼロ"
[ "$(getf '.monitor.mode')" = "targeted" ] || fail "C10: state の monitor.mode が targeted になっていない"
grep -q ',drift,implementing,observer-progress,0,targeted$' "$CSV" \
  || fail "C10: --mode targeted が CSV に記録されていない: $(tail -1 "$CSV")"
"$FW" monitor-set clean --mode bogus >/dev/null 2>&1 && fail "C10: 不正な --mode が受理されてしまった"
ok "C10: --mode（lite/targeted）が state + CSV に記録される。不正値は拒否"

echo "🎉 monitor-lens-csv 全ケース PASS"
