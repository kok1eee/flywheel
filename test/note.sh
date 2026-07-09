#!/usr/bin/env bash
# flywheel note（v0.8.41）検証: 進行中文脈の軽量スナップショット。
# 検証ケース:
#   C1) append   : `flywheel note` が .flywheel/notes.md に ISO8601 付き1行で追記される
#   C2) dormant  : state が無いとき note は exit 1 で拒否される
#   C3) greeter  : 最新3件だけが additionalContext に含まれる（最古1件は含まれない）
#   C4) status   : notes.md の全件が status 出力に含まれる
#   C5) archive  : done（fw_archive_plan 経由）で notes.md が plan/archive/<ts>/ へ退避され消える
# 足場（環境分離・state ヘルパ・setup_impl/setup_done_ready/run_hook）は test/chain-lib.sh に集約。
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/chain-lib.sh"

# GREETER / greeter_ctx() は chain-lib.sh 共有（heartbeat.sh と同型・rule-of-three）

# ---- C2: dormant では拒否（先に検証。state 未作成の初期状態を使う）----
rm -rf "$REPO_T/.flywheel"
out="$("$FW" note "no state" 2>&1)"; rc=$?
[ "$rc" = "1" ] || fail "C2: dormant で exit 1 のはず。実際=$rc"
echo "$out" | grep -q "state がありません" || fail "C2: 拒否理由が出力されていない: $out"
[ ! -f "$REPO_T/.flywheel/notes.md" ] || fail "C2: dormant なのに notes.md が作られた"
ok "C2: dormant では flywheel note が exit 1 で拒否される"

# ---- C1: append 形式 ----
setup_impl "true"
"$FW" note "最初のメモ" >/dev/null 2>&1 || fail "C1: note 実行が失敗"
[ -f "$REPO_T/.flywheel/notes.md" ] || fail "C1: notes.md が作られていない"
line="$(cat "$REPO_T/.flywheel/notes.md")"
echo "$line" | grep -qE '^- \[[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\] 最初のメモ$' \
  || fail "C1: 形式が ISO8601 付き1行になっていない: $line"
ok "C1: flywheel note が .flywheel/notes.md に ISO8601 形式で追記される"

# ---- C3: greeter は最新3件のみ（4件書いて最古1件が漏れることを確認）----
"$FW" note "2件目" >/dev/null 2>&1
"$FW" note "3件目" >/dev/null 2>&1
"$FW" note "4件目" >/dev/null 2>&1
ctx="$(greeter_ctx)"
echo "$ctx" | grep -q "最初のメモ" && fail "C3: greeter に最古の1件が含まれてしまっている（最新3件のはず）"
echo "$ctx" | grep -q "2件目" || fail "C3: greeter に2件目が含まれていない"
echo "$ctx" | grep -q "3件目" || fail "C3: greeter に3件目が含まれていない"
echo "$ctx" | grep -q "4件目" || fail "C3: greeter に4件目が含まれていない"
ok "C3: greeter は notes.md の最新3件だけを同梱する"

# ---- C4: status は全件表示 ----
status_out="$("$FW" status)"
echo "$status_out" | grep -q "最初のメモ" || fail "C4: status に最古の1件が含まれていない（全件表示のはず）"
echo "$status_out" | grep -q "4件目"       || fail "C4: status に最新の1件が含まれていない"
ok "C4: status は notes.md を全件表示する"

# ---- C5: done（fw_archive_plan 経由）で notes.md が archive へ退避され消える ----
setup_done_ready
"$FW" note "done 直前のメモ" >/dev/null 2>&1
rc="$(run_hook)"
[ "$rc" = "0" ] || fail "C5: done 到達の exit code は 0 のはず。実際=$rc"
[ "$(getf .phase)" = "done" ] || fail "C5: phase が done になっていない。実際=$(getf .phase)"
[ ! -f "$REPO_T/.flywheel/notes.md" ] || fail "C5: done 後も notes.md が .flywheel/ に残っている"
archived="$(find "$REPO_T/plan/archive" -name notes.md 2>/dev/null | head -1)"
[ -n "$archived" ] || fail "C5: plan/archive/<ts>/notes.md が見つからない"
grep -q "done 直前のメモ" "$archived" || fail "C5: 退避された notes.md に内容が無い: $archived"
ok "C5: done で notes.md が plan/archive/<ts>/ へ退避され .flywheel/ から消える"

echo "🎉 note 全ケース PASS"
