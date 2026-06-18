#!/usr/bin/env bash
# FR-33 検証: loop-driver の done 到達時に backlog を auto-chain で連続消化するか。
# live state を壊さないよう mktemp -d の使い捨て git リポで検証する。
# 検証ケース:
#   1) adopt chain   : 次が adopt 経路 → 自動 pop + phase=designing + exit 2（連鎖続行）
#   2) start chain   : 次が start 経路 → 自動 pop + phase=designing + exit 2（FR-35: HOTL 連鎖。steer は start-chain.sh）
#   3) NO_CHAIN      : FLYWHEEL_NO_CHAIN=1 → pop せず exit 0（従来挙動）
#   4) backlog 空    : 連鎖せず exit 0・phase=done
# 足場（環境分離・state ヘルパ・setup_done_ready/run_hook）は test/chain-lib.sh に集約。
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/chain-lib.sh"

# ---- ケース1: adopt chain ----
setup_done_ready
"$FW" add --adopt --eval "true" "goal B" >/dev/null 2>&1 || fail "add adopt 失敗"
rc="$(run_hook)"
[ "$rc" = "2" ]                    || fail "1: exit code は 2 のはず（連鎖続行）。実際=$rc"
[ "$(blc)" = "0" ]                 || fail "1: backlog は pop されて 0 のはず。実際=$(blc)"
[ "$(getf .phase)" = "designing" ]|| fail "1: 次 goal は designing のはず。実際=$(getf .phase)"
[ "$(getf .goal)" = "goal B" ]    || fail "1: goal は 'goal B' のはず。実際=$(getf .goal)"
[ "$(getf .entry)" = "adopt" ]    || fail "1: entry は adopt のはず。実際=$(getf .entry)"
ok "1) adopt chain: exit 2 + pop + 次 goal designing(adopt) 起動"

# ---- ケース2: start 経路は HOTL で連鎖（FR-35: 旧 hard-stop を廃止）----
# steer 内容の検証は test/start-chain.sh。ここは pop + exit 2 の退行防止のみ。
setup_done_ready
"$FW" add --eval "true" "goal C" >/dev/null 2>&1 || fail "add start 失敗"   # --adopt なし = start
rc="$(run_hook)"
[ "$rc" = "2" ]                    || fail "2: exit code は 2 のはず（HOTL 連鎖）。実際=$rc"
[ "$(blc)" = "0" ]                 || fail "2: backlog は pop されて 0 のはず。実際=$(blc)"
[ "$(getf .phase)" = "designing" ]|| fail "2: 次 goal は designing のはず。実際=$(getf .phase)"
[ "$(getf .entry)" = "start" ]    || fail "2: entry は start のはず。実際=$(getf .entry)"
ok "2) start chain: exit 2（pop + 次 goal designing 起動・HOTL 連鎖）"

# ---- ケース3: FLYWHEEL_NO_CHAIN=1 で従来挙動 ----
setup_done_ready
"$FW" add --adopt --eval "true" "goal D" >/dev/null 2>&1 || fail "add 失敗"
rc="$(FLYWHEEL_NO_CHAIN=1 bash -c 'FLYWHEEL_HOOK=1 bash "$0" </dev/null >/dev/null 2>&1; echo $?' "$HOOK")"
[ "$rc" = "0" ]                    || fail "3: exit code は 0 のはず。実際=$rc"
[ "$(blc)" = "1" ]                 || fail "3: NO_CHAIN は pop しない（1 件残る）。実際=$(blc)"
[ "$(getf .phase)" = "done" ]     || fail "3: phase は done のまま。実際=$(getf .phase)"
ok "3) NO_CHAIN: exit 0・pop せず・phase=done"

# ---- ケース4: backlog 空なら通常 done ----
setup_done_ready
rc="$(run_hook)"
[ "$rc" = "0" ]                    || fail "4: exit code は 0 のはず。実際=$rc"
[ "$(getf .phase)" = "done" ]     || fail "4: phase は done のはず。実際=$(getf .phase)"
ok "4) backlog 空: exit 0・phase=done"

echo "🎉 全ケース PASS"
