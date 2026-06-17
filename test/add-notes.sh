#!/usr/bin/env bash
# T1 検証: backlog notes 配線（add --notes → list[notes ✓] → next → state.notes → status / 後方互換）。
# live state を壊さないよう mktemp -d の使い捨てリポで検証する。
# grep は here-string（<<<）で受ける: `cmd | grep -q` は pipefail 下で grep の早期終了が
# 左コマンドを SIGPIPE で殺し、後続出力のある status で偽 FAIL になるため。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FW="$(cd "$SCRIPT_DIR/.." && pwd)/bin/flywheel"
fail() { echo "❌ FAIL: $1"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export CLAUDE_PLUGIN_DATA="$TMP/d"; mkdir -p "$CLAUDE_PLUGIN_DATA"  # 本番 CSV 汚染防止
cd "$TMP" && git init -q || fail "git init"

NOTES="boundary: foo.sh; 曖昧: なし"

# add --notes → backlog entry に notes、list が [notes ✓] を表示
"$FW" add --adopt --eval "true" --notes "$NOTES" "phase X" >/dev/null || fail "add --notes 失敗"
grep -q '\[notes ✓\]' <<<"$("$FW" list)" || fail "list が [notes ✓] を表示しない"

# next → state.notes へ引き継ぎ、status が notes 行を表示（design.md 検証 step3）
"$FW" next >/dev/null || fail "next 失敗"
got="$("$FW" get '.notes')"
[[ "$got" == "$NOTES" ]] || fail "state.notes 不一致: '$got'（期待: '$NOTES'）"
grep -qF "notes   : $NOTES" <<<"$("$FW" status)" || fail "status が notes 行を表示しない"
echo "✅ add --notes → list[notes ✓] → next → state.notes + status 表示 OK"

# 後方互換: notes 無し legacy entry でも壊れず、[notes ✓] も出ない（negative assert）
"$FW" reset >/dev/null
echo '{"goal":"legacy","eval_cmd":"","polish":true,"entry":"start"}' > "$TMP/.flywheel/backlog.jsonl"
_lst="$("$FW" list)"
grep -q 'legacy' <<<"$_lst" || fail "legacy list 表示失敗"
grep -qE 'legacy.*\[notes' <<<"$_lst" && fail "notes 無し entry に [notes ✓] が出た（negative assert）"
"$FW" next >/dev/null || fail "legacy next 失敗（後方互換）"
got2="$("$FW" get '.notes')"
[[ "$got2" == "" ]] || fail "legacy notes が空でない: '$got2'"
echo "✅ 後方互換（notes 無し entry）OK"

echo "🟢 add-notes PASS: notes 配線（add→list→next→state.notes→status）+ 後方互換"
