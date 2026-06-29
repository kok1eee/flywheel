#!/usr/bin/env bash
# 改善C(FR-50): monitor=clean を作業ツリーの fingerprint に紐付ける verdict 再利用を検証。
# clean ゲートが「指紋一致→done / 不一致→再council / 指紋なし→後方互換 done」を満たすか。
# chain-lib.sh の使い捨て git リポ（tracked seed.txt を変えて非空 diff を作る・.flywheel は untracked）を流用。
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/chain-lib.sh"   # REPO_T / FW / run_hook / setup_impl / state / getf / fail / ok（cd REPO_T 済み）

set_monitor_raw() { local s; s="$(state)"; jq "$1" "$s" > "$s.tmp" && mv "$s.tmp" "$s"; }

# C1: monitor-set clean が fingerprint を記録（tracked seed.txt を変えて非空 diff に）
setup_impl "true"
echo "c1-change" >> "$REPO_T/seed.txt"
"$FW" monitor-set clean "" "test C1" >/dev/null 2>&1 || fail "C1: monitor-set clean 失敗"
fp="$(getf '.monitor.fingerprint')"
{ [ -n "$fp" ] && [ "$fp" != "null" ]; } || fail "C1: fingerprint が記録されていない: '$fp'"
ok "C1 monitor-set clean → fingerprint 記録"

# C2: 指紋一致（コード不変）→ done（再 council せず）
run_hook >/dev/null
[ "$(getf '.phase')" = "done" ] || fail "C2: 指紋一致なのに done でない: phase=$(getf '.phase')"
ok "C2 指紋一致（無変更）→ done"

# C3: 指紋不一致（clean 記録後にコード変更）→ done すり抜け阻止・再 council
setup_impl "true"
echo "c3-a" >> "$REPO_T/seed.txt"
"$FW" monitor-set clean "" "test C3" >/dev/null 2>&1 || fail "C3: monitor-set clean 失敗"
echo "c3-b" >> "$REPO_T/seed.txt"   # clean 記録後に変更
run_hook >/dev/null
[ "$(getf '.phase')" != "done" ] || fail "C3: stale clean が done をすり抜けた（phase=done）"
[ "$(getf '.monitor.status')" = "pending" ] || fail "C3: 再 council のため pending に戻っていない: $(getf '.monitor.status')"
ok "C3 指紋不一致（変更後）→ done 阻止・再 council（pending）"

# C4: 後方互換 — 指紋なしの clean は従来どおり done（既存テスト/旧 verdict）
setup_impl "true"
echo "c4-change" >> "$REPO_T/seed.txt"
set_monitor_raw '.monitor = {status:"clean"}'   # fingerprint 無しで直接セット
run_hook >/dev/null
[ "$(getf '.phase')" = "done" ] || fail "C4: 指紋なし clean が done にならない（後方互換崩れ）: phase=$(getf '.phase')"
ok "C4 指紋なし clean → 従来どおり done（後方互換）"

# C5: load-bearing 不変条件 — 本番 repo の .gitignore が .flywheel を除外している
# （外れると jj diff に state.json が出て指紋が毎停止揺れ→clean が永久に done に届かない＝無限 re-council）
grep -q '\.flywheel' "$REPO/.gitignore" 2>/dev/null || fail "C5: 本番 .gitignore に .flywheel が無い（指紋安定性の load-bearing 不変条件が崩れる）"
ok "C5 .gitignore が .flywheel を除外（指紋安定性の不変条件）"

echo "✅ monitor-fingerprint: 全5ケース緑（C1 記録 / C2 一致→done / C3 不一致→再council / C4 後方互換 / C5 不変条件）"
