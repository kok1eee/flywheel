#!/usr/bin/env bash
# 検証: eval が command-not-found 系で落ちたら、eval-fail steer に「eval_cmd が怪しい→set-eval」の
# ヒントを出す。通常のテスト失敗（assert 落ち等）には出さない。
# 検証ケース:
#   C1) command-not-found : eval_cmd = 不在コマンド → stderr に set-eval ヒント有・exit 2
#   C2) 通常失敗          : eval_cmd = false（出力なし rc=1）→ ヒント無
# 足場（環境分離・state ヘルパ・任意 eval_cmd の setup_impl）は test/chain-lib.sh を再利用する。
# fresh start なので veto=0（cap=8 未満で eval-fail steer に届く）。
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/chain-lib.sh"

run_err() { FLYWHEEL_HOOK=1 bash "$HOOK" </dev/null 2>&1 >/dev/null; }

# ---- C1: command-not-found → set-eval ヒント有・exit 2（継続 steer）----
setup_impl "definitely_no_such_cmd_xyz"
rc="$(run_hook)"                       # chain-lib の run_hook（exit code）
setup_impl "definitely_no_such_cmd_xyz"  # 再 setup（veto を 0 に戻して steer を取る）
err="$(run_err)"
[ "$rc" = "2" ]                          || fail "C1: exit code は 2 のはず（継続 steer）。実際=$rc"
echo "$err" | grep -q "set-eval"         || fail "C1: command-not-found に set-eval ヒントが無い。stderr=$err"
ok "C1) command-not-found: set-eval ヒント有・exit 2"

# ---- C2: 通常のテスト失敗（出力なし rc=1）→ ヒント無 ----
setup_impl "false"
err="$(run_err)"
echo "$err" | grep -q "set-eval"         && fail "C2: 通常失敗に set-eval ヒントが出てはいけない。stderr=$err"
ok "C2) 通常失敗(出力なし): ヒント無"

# ---- C3: 出力に紛らわしい文字列を含む通常失敗 → ヒント無（誤検知の回帰ガード）----
# シェルの解決失敗でなく「アプリ出力に No such file が紛れる」通常失敗。広い grep だと誤発火していた。
setup_impl "echo 'config.yml: No such file or directory'; echo 'key: not found'; exit 1"
err="$(run_err)"
echo "$err" | grep -q "set-eval"         && fail "C3: 紛らわしい出力の通常失敗にヒントが出てはいけない（誤検知）。stderr=$err"
ok "C3) 紛らわしい出力の通常失敗: ヒント無（誤検知ガード）"

echo "🎉 eval-veto-hint 全ケース PASS"
