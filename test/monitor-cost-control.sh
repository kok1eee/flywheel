#!/usr/bin/env bash
# v0.8.42: monitor council のコスト比例制御（lite council / 標的再council / 安全弁）の
# loop-driver steer 出し分けを検証。
# Group A: last_drift の直接注入で hint 分岐ロジックを単体検証（heartbeat.sh の phase ゲート演習と同型）。
# Group B: 実際の drift(impl) ラウンドトリップで last_drift への退避（lens/level/diff_lines）を検証。
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/chain-lib.sh"

run_err() { FLYWHEEL_HOOK=1 bash "$HOOK" </dev/null 2>&1 >/dev/null; }

# REPO_T に未 track の実装ファイルを作り、fw_goal_diff_lines がちょうど $1 行を返すようにする
# （未track 新規ファイルは wc -l 丸ごと加算される規約・hooks/lib/common.sh:fw_repo_diff_lines。
# seq での N 行生成は test/polish-rename-skip.sh・test/multirepo-diff.sh と同じ既存イディオム）。
make_diff() { seq 1 "$1" > "$REPO_T/impl.sh"; }

# ---- Group A: hint 分岐（last_drift 直接注入） ----

# A1: last_drift 無し・diff 小・watch_focus 無し → lite council 可
setup_impl "true"; make_diff 50
err="$(run_err)"
echo "$err" | grep -q "lite council 可" || fail "A1: lite hint が出ていない: $err"
ok "A1: diff 小・初回・watch_focus 無し → lite council 可"

# A2: last_drift 無し・diff 大 → hint 無し（フル）
setup_impl "true"; make_diff 300
err="$(run_err)"
echo "$err" | grep -q "lite council 可" && fail "A2: diff 大なのに lite hint が出た: $err"
echo "$err" | grep -q "標的再council 可" && fail "A2: 標的hintも出てはいけない: $err"
ok "A2: diff 大（閾値以上） → hint 無し（フル）"

# A3: diff 小でも watch_focus 設定時はフル（安全弁①）
setup_impl "true"; make_diff 50
"$FW" watch-focus "重点X" >/dev/null || fail "A3: watch-focus 設定に失敗"
err="$(run_err)"
echo "$err" | grep -q "lite council 可" && fail "A3: watch_focus 設定時に lite hint が出た（安全弁①違反）: $err"
echo "$err" | grep -q "重点(watch-focus): 重点X" || fail "A3: watch_focus 自体の表示が消えている: $err"
ok "A3: watch_focus 設定時は diff 小でもフル（安全弁①）"

# A4: last_drift(implementing) 直接注入・修正 diff 小 → 標的再council 可 + 指摘 lens
setup_impl "true"; make_diff 80   # diff_after = 80
jq_patch "$(state)" '.last_drift={lens:"observer-behavior",level:"implementing",diff_lines:"50",ts:"2026-01-01T00:00:00Z"}' \
  || fail "A4: last_drift 注入失敗"
err="$(run_err)"
echo "$err" | grep -q "標的再council 可" || fail "A4: 標的hintが出ていない: $err"
echo "$err" | grep -q "observer-behavior" || fail "A4: 指摘レンズ名が steer に含まれていない: $err"
[ "$(getf '.last_drift')" = "null" ] || fail "A4: last_drift が one-shot クリアされていない"
ok "A4: drift 修正diff小 → 標的再council 可（指摘lensのみ）+ last_drift 消費"

# A5: last_drift(implementing) 直接注入・修正 diff 大（閾値超）→ 安全弁③でフル
setup_impl "true"; make_diff 400   # diff_after = 400
jq_patch "$(state)" '.last_drift={lens:"observer-progress",level:"implementing",diff_lines:"50",ts:"2026-01-01T00:00:00Z"}' \
  || fail "A5: last_drift 注入失敗"
err="$(run_err)"
echo "$err" | grep -q "標的再council 可" && fail "A5: 修正diff大なのに標的hintが出た（安全弁③違反）: $err"
[ "$(getf '.last_drift')" = "null" ] || fail "A5: last_drift が one-shot クリアされていない"
ok "A5: drift 修正diff大（閾値超） → 安全弁③でフル（標的hint無し）"

# A6: last_drift(design) 直接注入 → 安全弁②でフル（diff 小でも標的/lite 双方 hint 無し）
setup_impl "true"; make_diff 50
jq_patch "$(state)" '.last_drift={lens:"observer-requirement",level:"design",diff_lines:"10",ts:"2026-01-01T00:00:00Z"}' \
  || fail "A6: last_drift 注入失敗"
err="$(run_err)"
echo "$err" | grep -q "標的再council 可" && fail "A6: design level drift 後なのに標的hintが出た（安全弁②違反）: $err"
echo "$err" | grep -q "lite council 可" && fail "A6: design level drift 後なのに lite hintが出た（安全弁②違反）: $err"
[ "$(getf '.last_drift')" = "null" ] || fail "A6: last_drift が one-shot クリアされていない"
ok "A6: last_drift level=design → 安全弁②でフル（lite/標的 hint とも無し）"

# A7: watch_focus + last_drift(implementing) の組み合わせ → 安全弁①でフルだが last_drift は
# それでも one-shot クリアされる（monitor_hint 抽出前は watch_focus 分岐が先に return し
# last_drift クリアを素通りしていたバグの回帰・simplify altitude 指摘）。
setup_impl "true"; make_diff 80
jq_patch "$(state)" '.last_drift={lens:"observer-behavior",level:"implementing",diff_lines:"50",ts:"2026-01-01T00:00:00Z"}' \
  || fail "A7: last_drift 注入失敗"
"$FW" watch-focus "重点Y" >/dev/null || fail "A7: watch-focus 設定に失敗"
err="$(run_err)"
echo "$err" | grep -q "標的再council 可" && fail "A7: watch_focus 設定時に標的hintが出た（安全弁①違反）: $err"
[ "$(getf '.last_drift')" = "null" ] \
  || fail "A7: watch_focus 優先時も last_drift は one-shot クリアされるはず（stale 化バグの回帰）"
ok "A7: watch_focus + last_drift 併存でも安全弁①優先・last_drift は one-shot クリアされる（stale化バグ回帰）"

# ---- Group B: 実際の drift(impl) ラウンドトリップで last_drift 退避を検証 ----

# B1: monitor-set drift implementing --lens → 次の停止で last_drift に lens/level/diff_lines が退避される
setup_impl "true"; make_diff 60
run_hook >/dev/null   # 初回停止: monitor=pending へ
"$FW" monitor-set drift implementing "reason" --lens observer-progress >/dev/null \
  || fail "B1: monitor-set drift が失敗"
rc="$(run_hook)"   # drift(impl) 実行分岐 → last_drift 退避 → implementing に差し戻し
[ "$rc" = "2" ] || fail "B1: drift(impl) 差し戻しは exit 2 のはず。実際=$rc"
[ "$(getf '.last_drift.lens')" = "observer-progress" ] \
  || fail "B1: last_drift.lens が保存されていない。実際=$(getf '.last_drift.lens')"
[ "$(getf '.last_drift.level')" = "implementing" ] \
  || fail "B1: last_drift.level が保存されていない。実際=$(getf '.last_drift.level')"
[ "$(getf '.last_drift.diff_lines')" = "60" ] \
  || fail "B1: last_drift.diff_lines が保存されていない。実際=$(getf '.last_drift.diff_lines')"
[ "$(getf '.monitor')" = "null" ] || fail "B1: monitor はクリアされているはず"
ok "B1: drift(impl) 実行時に last_drift（lens/level/diff_lines）が退避される"

# ---- Group C: FR-38 融合パス（既定 fusion ON）でも lite hint が届くことの回帰検証 ----
# monitor が発見した drift(design)（2026-07-09）: enter_polish の融合分岐（$2=="monitor"）は
# monitor pending 初回分岐（monitor_hint 呼び出し）より先に発火するため、enter_polish 側で hint を
# 計算しないと diff 30〜250行の通常 goal で lite hint が既定設定では一度も出ない構造的欠陥だった。
# setup_impl は polish=false を強制するためこの回帰を検出できない＝ここでは既定のまま
# （polish=true・polished=false）にして融合パスを実際に通す。

setup_fused() {  # $1=eval_cmd。setup_impl と違い polish/polished は fw_init の既定のまま。
  rm -rf "$REPO_T/.flywheel" "$REPO_T/plan"
  "$FW" start "goal fused" --eval "$1" >/dev/null 2>&1 || fail "setup_fused: flywheel start 失敗"
  jq_patch "$(state)" '.phase="implementing" | .eval_src="explicit"' || fail "setup_fused: state 整形失敗"
}

# C1: 融合パス（既定）でも diff 30〜250行なら lite council 可 が steer に届く
setup_fused "true"; make_diff 80
err="$(run_err)"
[ "$(getf '.phase')" = "polish" ] || fail "C1: 融合で phase=polish になっていない。実際=$(getf '.phase')"
[ "$(getf '.monitor.status')" = "pending" ] || fail "C1: 融合で monitor=pending になっていない"
echo "$err" | grep -q "simplify" || fail "C1: 融合 steer に simplify が無い: $err"
echo "$err" | grep -q "flywheel:monitor" || fail "C1: 融合 steer に flywheel:monitor が無い: $err"
echo "$err" | grep -q "lite council 可" || fail "C1: 融合 steer に lite hint が届いていない（drift(design)の回帰）: $err"
ok "C1: FR-38 融合パス（既定）でも diff 小なら lite council 可 が steer に届く"

# C2: 融合パスでも diff 大なら lite hint は出ない（安全弁は融合パスでも効く）
setup_fused "true"; make_diff 300
err="$(run_err)"
echo "$err" | grep -q "lite council 可" && fail "C2: 融合パスで diff 大なのに lite hint が出た: $err"
ok "C2: FR-38 融合パスでも diff 大なら lite hint は出ない"

echo "🎉 monitor-cost-control 全ケース PASS"
