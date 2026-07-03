#!/usr/bin/env bash
# hook 発火の live positive control（FR-54）: design-gate の heartbeat touch と greeter の部分死 warn を検証。
# chain-lib.sh の隔離ハーネス（mktemp リポ・CLAUDE_PLUGIN_DATA を /tmp）で本番 heartbeat を汚さない。
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/chain-lib.sh"

GATE="$REPO/hooks/design-gate.sh"
GREETER="$REPO/hooks/session-greeter.sh"
HB="$CLAUDE_PLUGIN_DATA/heartbeat-design-gate"

gate_edit() {  # design-gate に Edit の PreToolUse を実入力で流す（$1=file_path）
  printf '{"tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$1" | FLYWHEEL_HOOK=1 bash "$GATE" >/dev/null 2>&1
  echo $?
}
greeter_ctx() {  # greeter を起動し additionalContext を返す
  bash "$GREETER" </dev/null 2>/dev/null | jq -r '.hookSpecificOutput.additionalContext // empty'
}

# C3(前半): dormant では design-gate は guard で抜け heartbeat を作らない
rm -rf "$REPO_T/.flywheel"; rm -f "$HB"
rc="$(gate_edit "$REPO_T/src.sh")"
[ "$rc" = "0" ] || fail "C3: dormant で design-gate が exit $rc"
[ ! -f "$HB" ] || fail "C3: dormant なのに heartbeat が作られた"
greeter_ctx | grep -q "発火痕跡" && fail "C3: dormant で greeter が warn した"
ok "C3: dormant は touch も warn もしない"

# C1: active（implementing）で design-gate 発火 → heartbeat 生成・exit 0
setup_impl "true"
rc="$(gate_edit "$REPO_T/src.sh")"
[ "$rc" = "0" ] || fail "C1: implementing の source 編集が exit $rc（門が誤ブロック）"
[ -f "$HB" ] || fail "C1: heartbeat が生成されていない"
ok "C1: design-gate 発火で heartbeat が touch される"

# C2: heartbeat を消す → greeter が warn / touch し直す → 無音
rm -f "$HB"
greeter_ctx | grep -q "発火痕跡がありません" || fail "C2: 痕跡欠如で greeter が warn しない"
touch "$HB"
greeter_ctx | grep -q "発火痕跡" && fail "C2: 痕跡があるのに greeter が warn した"
ok "C2: 痕跡欠如で warn・痕跡ありで無音"

# C2.5: mtime が閾値より古い → 停滞 warn（HEARTBEAT_STALE_DAYS=0 で全て停滞扱いにして演習）
out="$(HEARTBEAT_STALE_DAYS=0 bash "$GREETER" </dev/null 2>/dev/null | jq -r '.hookSpecificOutput.additionalContext // empty')"
printf '%s' "$out" | grep -q "止まっています" || fail "C2.5: 停滞 heartbeat で greeter が warn しない: $out"
ok "C2.5: mtime 停滞で warn（閾値は HEARTBEAT_STALE_DAYS で可変）"

# C4: データ領域が書き込み不能でも design-gate の挙動は不変（observation-only）
rm -f "$HB"
chmod 555 "$CLAUDE_PLUGIN_DATA"
rc="$(gate_edit "$REPO_T/src.sh")"
chmod 755 "$CLAUDE_PLUGIN_DATA"
[ "$rc" = "0" ] || fail "C4: heartbeat 書き込み不能で design-gate が exit $rc"
[ ! -f "$HB" ] || fail "C4: 書き込み不能なのに heartbeat ができている"
ok "C4: 計測失敗でも門の挙動は不変（observation-only）"

# C5: designing（gate 閉）でも発火痕跡は残る（block と独立）・source 編集は block される
rm -rf "$REPO_T/.flywheel" "$REPO_T/plan"
"$FW" start "goal hb" --eval "true" >/dev/null 2>&1 || fail "C5: start 失敗"
rm -f "$HB"
rc="$(gate_edit "$REPO_T/src.sh")"
[ "$rc" = "2" ] || fail "C5: designing の source 編集が exit $rc（block されるべき）"
[ -f "$HB" ] || fail "C5: block された発火で heartbeat が残っていない（touch は判定と独立のはず）"
ok "C5: block 経路でも発火痕跡は残る"

echo "🎉 heartbeat 全ケース PASS"
