#!/usr/bin/env bash
# FR-35 検証: loop-driver の done 到達時、次が start 経路 goal なら HOTL で連鎖する
# （hard-stop の exit 0 ではなく exit 2 + go/no-go grill steer）。
# live state を壊さないよう mktemp -d の使い捨て git リポで検証する。
# 検証ケース:
#   C1) start chain : 次が start 経路 → 自動 pop + phase=designing + exit 2（連鎖続行）
#   C2) steer 内容  : stderr に go/no-go・discovery・「判断は self-answer しない」マーカーを含む
#   C3) NO_CHAIN    : FLYWHEEL_NO_CHAIN=1 → pop せず exit 0・phase=done（従来 hand-back 維持）
# 足場（環境分離・state ヘルパ・setup_done_ready/run_hook）は test/chain-lib.sh に集約。
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/chain-lib.sh"

# ---- C1: start 経路は exit 2 で連鎖 ----
setup_done_ready
"$FW" add --eval "true" "goal S" >/dev/null 2>&1 || fail "add start 失敗"   # --adopt なし = start
rc="$(run_hook)"
[ "$rc" = "2" ]                    || fail "C1: exit code は 2 のはず（HOTL 連鎖）。実際=$rc"
[ "$(blc)" = "0" ]                 || fail "C1: backlog は pop されて 0 のはず。実際=$(blc)"
[ "$(getf .phase)" = "designing" ]|| fail "C1: 次 goal は designing のはず。実際=$(getf .phase)"
[ "$(getf .goal)" = "goal S" ]    || fail "C1: goal は 'goal S' のはず。実際=$(getf .goal)"
[ "$(getf .entry)" = "start" ]    || fail "C1: entry は start のはず。実際=$(getf .entry)"
ok "C1) start chain: exit 2 + pop + 次 goal designing(start) 起動"

# ---- C2: steer 内容（go/no-go・discovery・判断は self-answer しない）----
setup_done_ready
"$FW" add --eval "true" "goal T" >/dev/null 2>&1 || fail "add start 失敗"
err="$(FLYWHEEL_HOOK=1 bash "$HOOK" </dev/null 2>&1 >/dev/null)"
echo "$err" | grep -q "go/no-go"          || fail "C2: steer に go/no-go gate が無い"
echo "$err" | grep -q "no-go →"           || fail "C2: steer に no-go ブランチ（discovery せず停止）が無い"
echo "$err" | grep -q "discovery を回す"  || fail "C2: steer に go-branch の discovery 実行指示が無い"
echo "$err" | grep -q "self-answer せず"  || fail "C2: steer に「判断は self-answer せず grill」が無い"
ok "C2) steer: go/no-go + no-go 停止 + discovery 実行 + 判断は self-answer しない を含む"

# ---- C3: FLYWHEEL_NO_CHAIN=1 で従来 hand-back（pop せず stop）----
setup_done_ready
"$FW" add --eval "true" "goal U" >/dev/null 2>&1 || fail "add start 失敗"
rc="$(FLYWHEEL_NO_CHAIN=1 bash -c 'FLYWHEEL_HOOK=1 bash "$0" </dev/null >/dev/null 2>&1; echo $?' "$HOOK")"
[ "$rc" = "0" ]                    || fail "C3: exit code は 0 のはず。実際=$rc"
[ "$(blc)" = "1" ]                 || fail "C3: NO_CHAIN は pop しない（1 件残る）。実際=$(blc)"
[ "$(getf .phase)" = "done" ]     || fail "C3: phase は done のまま。実際=$(getf .phase)"
ok "C3) NO_CHAIN: exit 0・pop せず・phase=done（従来 hand-back 維持）"

echo "🎉 start-chain 全ケース PASS"
