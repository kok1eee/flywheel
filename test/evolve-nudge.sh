#!/usr/bin/env bash
# 改善A: session-greeter の evolve 停滞リマインダ（fw_evolve_staleness）を検証する。
# live state / 本番 CSV を汚さないよう mktemp の使い捨て領域で実行（CLAUDE_PLUGIN_DATA を /tmp に・
# 作業ディレクトリは非 git で dormant 化）。タイムスタンプは date -u -d で相対生成し決定的にする。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
GREETER="$REPO/hooks/session-greeter.sh"

fail() { echo "❌ FAIL: $1"; exit 1; }
ok()   { echo "✅ $1"; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
DATA="$TMP/data"; mkdir -p "$DATA"
WORK="$TMP/work"; mkdir -p "$WORK"   # 非 git → fw_repo_root は pwd へ落ち state 無し＝dormant
CSV="$DATA/skill-usage.csv"
ISO() { date -u -d "$1" +%Y-%m-%dT%H:%M:%SZ; }   # 例: ISO '30 days ago'

# dormant greeting を temp 環境で実行して stdout を返す
run_greeter() {
  ( cd "$WORK" && env CLAUDE_PLUGIN_DATA="$DATA" FLYWHEEL_OFF= FLYWHEEL_PLAN= \
      bash "$GREETER" 2>/dev/null )
}

# C1: 最終 evolve が 30 日前 → 日数閾値(7)で停滞リマインダが出る
printf 'timestamp,skill\n%s,flywheel:evolve\n' "$(ISO '30 days ago')" > "$CSV"
out="$(run_greeter)"
echo "$out" | grep -q 'evolve 未実行' || fail "C1: 30日前 evolve でリマインダが出ない"
echo "$out" | grep -q 'flywheel は dormant' || fail "C1: dormant 文面が出ていない"
ok "C1 stale(30日) → リマインダ表示"

# C2: 最終 evolve が今日・後続 goal 0 → 非停滞でリマインダは出ない
printf 'timestamp,skill\n%s,flywheel:evolve\n' "$(ISO 'now')" > "$CSV"
out="$(run_greeter)"
if echo "$out" | grep -q 'evolve 未実行'; then fail "C2: fresh(今日・goal0) でリマインダが出てしまう"; fi
echo "$out" | grep -q 'flywheel は dormant' || fail "C2: dormant 文面が出ていない"
ok "C2 fresh → リマインダ非表示"

# C3: evolve は2日前(日数閾値未満)だが後続 goal が5件 → goal 数閾値(5)で停滞発火
{ printf 'timestamp,skill\n%s,flywheel:evolve\n' "$(ISO '2 days ago')"
  for _ in 1 2 3 4 5; do printf '%s,goal:start\n' "$(ISO '1 day ago')"; done
} > "$CSV"
out="$(run_greeter)"
echo "$out" | grep -q 'evolve 未実行' || fail "C3: goal5件でリマインダが出ない（goal 数閾値の発火失敗）"
ok "C3 goals>=5 → リマインダ表示（日数でなく goal 数で発火）"

# C4: CSV 欠落 → 無音・greeter は通常 dormant 文面を出す（クラッシュしない）
rm -f "$CSV"
out="$(run_greeter)"; rc=$?
[[ "$rc" -eq 0 ]] || fail "C4: CSV 欠落で greeter が非ゼロ終了（壊れた）"
if echo "$out" | grep -q 'evolve 未実行'; then fail "C4: CSV 欠落でリマインダが出てしまう"; fi
echo "$out" | grep -q 'flywheel は dormant' || fail "C4: CSV 欠落で dormant 文面が出ない（greeter が壊れた）"
ok "C4 CSV欠落 → 無音・dormant 文面は健在"

# --- active=done greeting も検証（design: dormant と done の両方に差す。監視 council 指摘で追加）---
# WORK に done state を置くと greeter は active 経路（phase=done）を通る
mkdir -p "$WORK/.flywheel"
printf '%s\n' '{"phase":"done","goal":"test goal A","eval_cmd":"true","eval_src":"explicit","polish":false,"polished":true}' > "$WORK/.flywheel/state.json"

# C5: done phase + stale CSV → done greeting にもリマインダが出る
printf 'timestamp,skill\n%s,flywheel:evolve\n' "$(ISO '30 days ago')" > "$CSV"
out="$(run_greeter)"
echo "$out" | grep -q 'phase=done' || fail "C5: done state なのに done greeting が出ていない"
echo "$out" | grep -q 'evolve 未実行' || fail "C5: done greeting に停滞リマインダが出ない"
ok "C5 done+stale → done greeting にリマインダ表示"

# C6: done phase + fresh CSV → done greeting だが非停滞でリマインダ無し（done 経路でも閾値が効く）
printf 'timestamp,skill\n%s,flywheel:evolve\n' "$(ISO 'now')" > "$CSV"
out="$(run_greeter)"
echo "$out" | grep -q 'phase=done' || fail "C6: done greeting が出ていない"
if echo "$out" | grep -q 'evolve 未実行'; then fail "C6: fresh なのに done greeting にリマインダが出てしまう"; fi
ok "C6 done+fresh → リマインダ非表示"

# C7: evolve 記録なし（goal はある）→「未実行（記録なし）」分岐（dormant に戻す）
rm -f "$WORK/.flywheel/state.json"
{ printf 'timestamp,skill\n'; printf '%s,goal:start\n' "$(ISO '1 day ago')"; } > "$CSV"
out="$(run_greeter)"
echo "$out" | grep -q '記録なし' || fail "C7: evolve 記録なしで『未実行（記録なし）』が出ない"
ok "C7 記録なし → リマインダ表示"

echo "✅ evolve-nudge: 全7ケース緑（dormant C1-C4 / done C5-C6 / 記録なし C7）"
