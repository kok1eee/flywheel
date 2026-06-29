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

# --- FR-A/B: 宣言 sibling repo（state.repos）を指紋に含める（multi-repo stale clean 穴塞ぎ） ---
# 使い捨て sibling git リポを1つ作る。FW_ROOT は無変更のまま sibling だけ動かして指紋が立つかを見る。
SIB="$TMP/sibling"; mkdir -p "$SIB"
( cd "$SIB" && git init -q && git config user.email t@example.com && git config user.name tester \
  && echo sib-seed > sib.txt && git add -A && git commit -qm init ) || fail "sibling git 初期化失敗"

# C6: FW_ROOT 無変更 + sibling 変更 → 指紋が非空（穴の本体）。
# 旧実装は FW_ROOT diff が空だと空指紋→後方互換 done＝sibling 変更を見落とす。新実装は連結後に空判定。
setup_impl "true"
git -C "$REPO_T" checkout -- seed.txt   # 先行ケース（C1-C4）の seed.txt 追記を戻し FW_ROOT diff を真に空にする
# 判別根拠を pin: repos 未宣言・FW_ROOT 無変更なら指紋は空（後方互換 done）。これが空でないと C6 が false-pass し得る。
"$FW" monitor-set clean "" "C6 pre" >/dev/null 2>&1 || fail "C6: monitor-set clean(pre) 失敗"
fp_pre="$(getf '.monitor.fingerprint')"
{ [ -z "$fp_pre" ] || [ "$fp_pre" = "null" ]; } || fail "C6: FW_ROOT 無変更・repos 未宣言なら指紋は空のはず（判別根拠が崩れている）: '$fp_pre'"
"$FW" repos "$SIB" >/dev/null 2>&1 || fail "C6: flywheel repos 登録失敗"
echo "c6-sibling-change" >> "$SIB/sib.txt"   # FW_ROOT は触らず sibling のみ変更
"$FW" monitor-set clean "" "test C6" >/dev/null 2>&1 || fail "C6: monitor-set clean 失敗"
fp6="$(getf '.monitor.fingerprint')"
{ [ -n "$fp6" ] && [ "$fp6" != "null" ]; } || fail "C6: FW_ROOT 無変更でも sibling 変更があれば指紋が立つべき（穴未塞ぎ）: '$fp6'"
ok "C6 FW_ROOT 無変更（pre=空を pin）+ sibling 変更 → 指紋が立つ（穴の本体を塞ぐ）"

# C7: sibling だけ変更 → stale clean を done すり抜けさせず再 council（C3 の sibling 版）。
echo "c7-sibling-more" >> "$SIB/sib.txt"   # clean 記録後に sibling を再変更
run_hook >/dev/null
[ "$(getf '.phase')" != "done" ] || fail "C7: sibling の stale clean が done をすり抜けた（phase=done）"
[ "$(getf '.monitor.status')" = "pending" ] || fail "C7: 再 council のため pending に戻っていない: $(getf '.monitor.status')"
ok "C7 sibling 変更後の stale clean → done 阻止・再 council（pending）"

# C8: sibling 側でも state 等の untracked（.flywheel）は指紋に出ない（C5 の sibling 版・指紋安定性の不変条件）。
# test は git 機構（git diff $base は untracked を除外）で検証。本番 jj は untracked を snapshot するため
# sibling 側 .gitignore に .flywheel が要る点は機構が違う（improvements.md の test=git / prod=jj メモ参照）が、
# 「sibling の state 書き込みで指紋が揺れない」load-bearing 不変条件は両機構で同結果になる。
"$FW" monitor-set clean "" "C8 base" >/dev/null 2>&1 || fail "C8: monitor-set clean(base) 失敗"
fp8_base="$(getf '.monitor.fingerprint')"
mkdir -p "$SIB/.flywheel"; echo '{"phase":"x"}' > "$SIB/.flywheel/state.json"   # sibling に untracked state を作る
"$FW" monitor-set clean "" "C8 after" >/dev/null 2>&1 || fail "C8: monitor-set clean(after) 失敗"
[ "$fp8_base" = "$(getf '.monitor.fingerprint')" ] || fail "C8: sibling の untracked .flywheel が指紋を変えた（指紋安定性の不変条件が崩れる）"
ok "C8 sibling の untracked .flywheel は指紋に出ない（指紋安定性の不変条件）"

# C9: mid-goal commit でも指紋が揺れない（凍結 .baseline_rev 規約の回帰ガード）。
# 旧バグ: FW_ROOT base に live `fw_baseline_rev`(=jj @- / git HEAD) を読むと commit で HEAD が前進し
# `diff --from HEAD` が空に潰れて指紋ゼロリセット→false re-council。凍結 baseline 読みでのみ done に到達する。
setup_impl "true"
echo "c9-impl-change" >> "$REPO_T/seed.txt"
git -C "$REPO_T" add seed.txt >/dev/null 2>&1   # seed.txt のみ stage（.flywheel を staged にすると state churn が指紋に漏れる）
"$FW" monitor-set clean "" "C9 clean" >/dev/null 2>&1 || fail "C9: monitor-set clean 失敗"
git -C "$REPO_T" commit -qm "mid-goal checkpoint" seed.txt >/dev/null 2>&1 || fail "C9: mid-goal commit 失敗"
run_hook >/dev/null
[ "$(getf '.phase')" = "done" ] || fail "C9: mid-goal commit で指紋がゼロリセットし false re-council した（live baseline バグ）: phase=$(getf '.phase')"
ok "C9 mid-goal commit でも指紋安定（凍結 baseline）→ done（false re-council なし）"

echo "✅ monitor-fingerprint: 全9ケース緑（C1 記録 / C2 一致→done / C3 不一致→再council / C4 後方互換 / C5 不変条件 / C6 sibling 指紋 / C7 sibling stale clean / C8 sibling 指紋安定性 / C9 mid-goal commit 安定）"
