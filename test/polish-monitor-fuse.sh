#!/usr/bin/env bash
# FR-38 検証: polish+monitor steer の融合（往復削減）。
#   C1) 融合(既定)   : polish 必要時 → exit2 + phase=polish + polished=true + monitor=pending prime
#                      + steer に simplify と flywheel:monitor 両方
#   C2) エスケープ    : FLYWHEEL_NO_FUSE=1 → exit2 + polished=true + monitor を prime しない
#                      + steer は simplify のみ（monitor 無し）＝従来の分離2ステップ
#   C3) 融合後の解決  : polished=true + monitor=clean + eval緑 → phase=done（融合ターン完了後の解決）
# 足場は chain-lib を再利用。
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/chain-lib.sh"

# polish 必要・monitor 未判定の状態。baseline_rev="" で fw_goal_diff_lines を空にし、
# should_polish を必ず「polish 要」に倒す（diff 計測不能 → skip しない）。
prime_polish() {
  setup_impl "true"
  local s; s="$(state)"
  jq '.polish=true | .polished=false | .monitor=null | .baseline_rev=""' \
    "$s" > "$s.tmp" && mv "$s.tmp" "$s" || fail "prime_polish 失敗"
}
run_err()        { FLYWHEEL_HOOK=1 bash "$HOOK" </dev/null 2>&1 >/dev/null; }
run_nofuse()     { FLYWHEEL_NO_FUSE=1 FLYWHEEL_HOOK=1 bash "$HOOK" </dev/null >/dev/null 2>&1; echo $?; }
run_nofuse_err() { FLYWHEEL_NO_FUSE=1 FLYWHEEL_HOOK=1 bash "$HOOK" </dev/null 2>&1 >/dev/null; }

# ---- C1: 融合(既定) ----
prime_polish
rc="$(run_hook)"
[ "$rc" = "2" ]                          || fail "C1: exit 2 のはず（継続）。実際=$rc"
[ "$(getf .phase)" = "polish" ]          || fail "C1: phase=polish のはず。実際=$(getf .phase)"
[ "$(getf .polished)" = "true" ]         || fail "C1: polished=true のはず"
[ "$(getf .monitor.status)" = "pending" ]|| fail "C1: monitor=pending prime のはず。実際=$(getf .monitor.status)"
prime_polish; err="$(run_err)"
echo "$err" | grep -q "simplify"          || fail "C1: steer に simplify が無い"
echo "$err" | grep -q "flywheel:monitor"  || fail "C1: steer に flywheel:monitor が無い"
ok "C1) 融合: exit2 + monitor pending prime + simplify/monitor 両 steer"

# ---- C2: エスケープハッチ（FLYWHEEL_NO_FUSE=1）----
prime_polish
rc="$(run_nofuse)"
[ "$rc" = "2" ]                          || fail "C2: exit 2 のはず。実際=$rc"
[ "$(getf .polished)" = "true" ]         || fail "C2: polished=true のはず"
[ "$(getf .monitor.status)" != "pending" ]|| fail "C2: NO_FUSE は monitor を prime しないはず。実際=$(getf .monitor.status)"
prime_polish; err="$(run_nofuse_err)"
echo "$err" | grep -q "simplify"          || fail "C2: steer に simplify が無い"
echo "$err" | grep -q "flywheel:monitor"  && fail "C2: NO_FUSE の steer に monitor が出てはいけない"
ok "C2) エスケープ: monitor prime せず・steer は simplify のみ（従来挙動）"

# ---- C3: 融合 entry を通って → monitor clean 記録 → done（完全チェーン）----
# prime→run_hook で融合発火（polished=true・monitor=pending）→ model が simplify+monitor を実行し
# clean を記録した想定 → 次停止が done に解決するか。融合の出力 state を起点にするのが要点。
prime_polish
run_hook >/dev/null                      # 融合発火
[ "$(getf .monitor.status)" = "pending" ]|| fail "C3 前提: 融合で monitor=pending のはず"
s="$(state)"; jq '.monitor={status:"clean"}' "$s" > "$s.tmp" && mv "$s.tmp" "$s" || fail "C3: monitor 記録失敗"
rc="$(run_hook)"
[ "$rc" = "0" ]                          || fail "C3: done は exit 0 のはず。実際=$rc"
[ "$(getf .phase)" = "done" ]            || fail "C3: phase=done のはず。実際=$(getf .phase)"
ok "C3) 融合 entry→monitor clean→done（完全チェーン）"

# ---- C4: degrade 安全 — model が monitor を飛ばす → pending 継続 → done にしない ----
# 融合の安全根拠（default-ON の前提）: monitor を prime してあるので model が飛ばしても次停止の
# monitor pending 分岐が拾って再 steer ＝ done をすり抜けない。
prime_polish
run_hook >/dev/null                      # 融合発火（monitor=pending のまま＝model が monitor 未実行を模擬）
rc="$(run_hook)"
[ "$rc" = "2" ]                          || fail "C4: pending は exit 2（再 steer）のはず。実際=$rc"
[ "$(getf .phase)" != "done" ]           || fail "C4: monitor 未記録で done にしてはいけない（degrade 安全）"
ok "C4) degrade: monitor 飛ばし→pending 継続→done すり抜けなし"

echo "🎉 polish-monitor-fuse 全ケース PASS"
