#!/usr/bin/env bash
# FR-33 検証: loop-driver の done 到達時に backlog を auto-chain で連続消化するか。
# live state を壊さないよう mktemp -d の使い捨て git リポで検証する。
# 検証ケース:
#   1) adopt checkpoint : 次が adopt 経路 → pop せず checkpoint steer + exit 2（Goal C・ROADMAP:54）
#   2) checkpoint 内容   : stderr に AskUserQuestion・はい/いいえ分岐・idle timeout 注記を含む
#   3) start chain       : 次が start 経路 → 自動 pop + phase=designing + exit 2（FR-35: HOTL 連鎖。steer は start-chain.sh）
#   4) NO_CHAIN          : FLYWHEEL_NO_CHAIN=1 → pop せず exit 0（従来挙動。checkpoint より優先）
#   5) backlog 空        : 連鎖せず exit 0・phase=done
# 足場（環境分離・state ヘルパ・setup_done_ready/run_hook）は test/chain-lib.sh に集約。
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/chain-lib.sh"

# ---- ケース1: adopt は checkpoint で止まる（pop しない・Goal C）----
setup_done_ready
"$FW" add --adopt --eval "true" "goal B" >/dev/null 2>&1 || fail "add adopt 失敗"
rc="$(run_hook)"
[ "$rc" = "2" ]                    || fail "1: exit code は 2 のはず（checkpoint steer）。実際=$rc"
[ "$(blc)" = "1" ]                 || fail "1: backlog は pop されず 1 件残るはず。実際=$(blc)"
[ "$(getf .phase)" = "done" ]     || fail "1: 次 goal を起動しない＝phase は done のまま。実際=$(getf .phase)"
ok "1) adopt checkpoint: exit 2 + pop せず + phase=done のまま（次 goal 未起動）"

# ---- ケース2: checkpoint steer 内容（AskUserQuestion・はい/いいえ・idle timeout）----
setup_done_ready
"$FW" add --adopt --eval "true" "goal B2" >/dev/null 2>&1 || fail "add adopt 失敗"
err="$(FLYWHEEL_HOOK=1 bash "$HOOK" </dev/null 2>&1 >/dev/null)"
echo "$err" | grep -q "AskUserQuestion"        || fail "2: steer に AskUserQuestion が無い"
echo "$err" | grep -q "次の goal に進みますか" || fail "2: steer に checkpoint の問いが無い"
echo "$err" | grep -q "はい"                   || fail "2: steer に「はい」分岐が無い"
echo "$err" | grep -q "いいえ/あとで"          || fail "2: steer に「いいえ/あとで」分岐が無い"
echo "$err" | grep -q "idle timeout"           || fail "2: steer に idle timeout オプトイン注記が無い"
ok "2) checkpoint steer: AskUserQuestion + はい/いいえ分岐 + idle timeout 注記を含む"

# ---- ケース3: start 経路は checkpoint を経ず HOTL で連鎖（FR-35: 旧 hard-stop を廃止）----
# steer 内容の検証は test/start-chain.sh。ここは pop + exit 2 の退行防止のみ。
setup_done_ready
"$FW" add --eval "true" "goal C" >/dev/null 2>&1 || fail "add start 失敗"   # --adopt なし = start
rc="$(run_hook)"
[ "$rc" = "2" ]                    || fail "3: exit code は 2 のはず（HOTL 連鎖）。実際=$rc"
[ "$(blc)" = "0" ]                 || fail "3: backlog は pop されて 0 のはず。実際=$(blc)"
[ "$(getf .phase)" = "designing" ]|| fail "3: 次 goal は designing のはず。実際=$(getf .phase)"
[ "$(getf .entry)" = "start" ]    || fail "3: entry は start のはず。実際=$(getf .entry)"
ok "3) start chain: exit 2（pop + 次 goal designing 起動・checkpoint 経由しない）"

# ---- ケース4: FLYWHEEL_NO_CHAIN=1 で従来挙動（adopt でも checkpoint より優先）----
setup_done_ready
"$FW" add --adopt --eval "true" "goal D" >/dev/null 2>&1 || fail "add 失敗"
rc="$(FLYWHEEL_NO_CHAIN=1 bash -c 'FLYWHEEL_HOOK=1 bash "$0" </dev/null >/dev/null 2>&1; echo $?' "$HOOK")"
[ "$rc" = "0" ]                    || fail "4: exit code は 0 のはず。実際=$rc"
[ "$(blc)" = "1" ]                 || fail "4: NO_CHAIN は pop しない（1 件残る）。実際=$(blc)"
[ "$(getf .phase)" = "done" ]     || fail "4: phase は done のまま。実際=$(getf .phase)"
ok "4) NO_CHAIN: exit 0・pop せず・phase=done（adopt checkpoint より優先）"

# ---- ケース5: backlog 空なら通常 done ----
setup_done_ready
rc="$(run_hook)"
[ "$rc" = "0" ]                    || fail "5: exit code は 0 のはず。実際=$rc"
[ "$(getf .phase)" = "done" ]     || fail "5: phase は done のはず。実際=$(getf .phase)"
ok "5) backlog 空: exit 0・phase=done"

echo "🎉 全ケース PASS"
