#!/usr/bin/env bash
# FR-33 検証: loop-driver の done 到達時に backlog を auto-chain で連続消化するか。
# live state を壊さないよう mktemp -d の使い捨て git リポで検証する。
# 検証ケース:
#   1) adopt chain   : 次が adopt 経路 → 自動 pop + phase=designing + exit 2（連鎖続行）
#   2) start 停止    : 次が start 経路 → 自動 pop するが exit 0（HITL hand-back）
#   3) NO_CHAIN      : FLYWHEEL_NO_CHAIN=1 → pop せず exit 0（従来挙動）
#   4) backlog 空    : 連鎖せず exit 0・phase=done
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
FW="$REPO/bin/flywheel"
HOOK="$REPO/hooks/loop-driver.sh"

fail() { echo "❌ FAIL: $1"; exit 1; }
ok()   { echo "✅ $1"; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export CLAUDE_PLUGIN_DATA="$TMP/data"; mkdir -p "$CLAUDE_PLUGIN_DATA"   # 本番 CSV 汚染防止
export PATH="$REPO/bin:$PATH"          # hook 内 FW_CLI=flywheel を repo の bin に固定
unset FLYWHEEL_NO_CHAIN FLYWHEEL_OFF 2>/dev/null || true

REPO_T="$TMP/repo"; mkdir -p "$REPO_T"
( cd "$REPO_T" && git init -q && git config user.email t@example.com && git config user.name tester \
  && echo seed > seed.txt && git add -A && git commit -qm init ) || fail "git 初期化失敗"
cd "$REPO_T" || fail "cd 失敗"

state() { echo "$REPO_T/.flywheel/state.json"; }
getf()  { jq -r "$1" "$(state)"; }
blc()   { local b="$REPO_T/.flywheel/backlog.jsonl"; [ -s "$b" ] && grep -c . "$b" || echo 0; }

# goal A を done 直前の姿（implementing + 全ゲート緑）に整える
setup_done_ready() {
  rm -rf "$REPO_T/.flywheel" "$REPO_T/plan"
  "$FW" start "goal A" --eval "true" >/dev/null 2>&1 || fail "flywheel start 失敗"
  local s; s="$(state)"
  jq '.phase="implementing" | .eval_cmd="true" | .eval_src="explicit" | .polish=false | .polished=true | .monitor={status:"clean"}' \
    "$s" > "$s.tmp" && mv "$s.tmp" "$s" || fail "state 整形失敗"
}

run_hook() { FLYWHEEL_HOOK=1 bash "$HOOK" </dev/null >/dev/null 2>&1; echo $?; }

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

# ---- ケース2: start 経路は停止して人間に返す ----
setup_done_ready
"$FW" add --eval "true" "goal C" >/dev/null 2>&1 || fail "add start 失敗"   # --adopt なし = start
rc="$(run_hook)"
[ "$rc" = "0" ]                    || fail "2: exit code は 0 のはず（HITL hand-back）。実際=$rc"
[ "$(blc)" = "0" ]                 || fail "2: backlog は pop されて 0 のはず。実際=$(blc)"
[ "$(getf .entry)" = "start" ]    || fail "2: entry は start のはず。実際=$(getf .entry)"
ok "2) start 停止: exit 0（pop はするが連鎖せず人間へ）"

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
