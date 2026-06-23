#!/usr/bin/env bash
# fw_chain_checkpoint（FR-46）の検証。done→chain 境界で完了 goal を独立 change に確定し履歴粒度を保つ。
# C1) jj: describe(完了 goal をラベル) + jj new(空の新 change) で分離
# C2) git: degrade（commit せず・エラー終了しない）
# C3) FLYWHEEL_NO_CHECKPOINT=1 で無効化（@ 不変）
# live state を汚さないよう mktemp の使い捨てリポで検証する。
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
COMMON="$REPO/hooks/lib/common.sh"
fail() { echo "❌ FAIL: $1"; exit 1; }

command -v jj >/dev/null 2>&1 || { echo "⏭️  jj 未インストール → chain-checkpoint テスト skip"; exit 0; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export CLAUDE_PLUGIN_DATA="$TMP/data"; mkdir -p "$CLAUDE_PLUGIN_DATA"   # 本番 CSV 汚染防止

# repo dir 内で common.sh を source して fw_chain_checkpoint を呼ぶ（FW_ROOT は cwd から解決される）。
run_checkpoint() { ( cd "$1" && bash -c 'source "'"$COMMON"'"; fw_chain_checkpoint' ); }

# --- C1) jj path: 完了 goal を describe + 空の新 change に分離 ---
JJ="$TMP/jjrepo"; mkdir -p "$JJ"
( cd "$JJ" && jj git init >/dev/null 2>&1 \
    && jj config set --repo user.name tester >/dev/null 2>&1 \
    && jj config set --repo user.email t@example.com >/dev/null 2>&1 ) || fail "jj git init/config 失敗"
mkdir -p "$JJ/.flywheel"; printf '{"phase":"done","goal":"FR-X: 何かを実装する goal"}' > "$JJ/.flywheel/state.json"
echo work > "$JJ/impl.txt"   # goal N の work（@ に乗る）
run_checkpoint "$JJ" >/dev/null 2>&1 || fail "fw_chain_checkpoint(jj) がエラー終了"
desc="$( cd "$JJ" && jj log -r '@-' --no-graph -T 'description.first_line()' 2>/dev/null )"
printf '%s' "$desc" | grep -q "chain checkpoint" || fail "jj: @- が checkpoint described でない（desc=[$desc]）"
( cd "$JJ" && jj log -r '@' --no-graph -T 'if(empty,"E","F")' 2>/dev/null | grep -q E ) || fail "jj: @ が空の新 change でない"
echo "✅ C1) jj: 完了 goal を確定（$desc）+ 空の新 change"

# --- C2) git path: degrade（commit せず・エラーなし）---
GT="$TMP/gitrepo"; mkdir -p "$GT"
( cd "$GT" && git init -q && git config user.email t@e.com && git config user.name t \
    && echo seed > s.txt && git add -A && git commit -qm init ) || fail "git 初期化失敗"
mkdir -p "$GT/.flywheel"; printf '{"phase":"done","goal":"FR-Y"}' > "$GT/.flywheel/state.json"
echo work > "$GT/impl.txt"
before="$( cd "$GT" && git rev-parse HEAD )"
run_checkpoint "$GT" >/dev/null 2>&1 || fail "fw_chain_checkpoint(git) がエラー終了（degrade のはず）"
after="$( cd "$GT" && git rev-parse HEAD )"
[ "$before" = "$after" ] || fail "git: degrade のはずが HEAD が動いた（commit された）"
echo "✅ C2) git: degrade（commit せず・エラーなし）"

# --- C3) FLYWHEEL_NO_CHECKPOINT=1 で無効化（@ change_id 不変）---
id_before="$( cd "$JJ" && jj log -r '@' --no-graph -T 'change_id' 2>/dev/null )"
( cd "$JJ" && FLYWHEEL_NO_CHECKPOINT=1 bash -c 'source "'"$COMMON"'"; fw_chain_checkpoint' ) || fail "NO_CHECKPOINT 呼び出しがエラー"
id_after="$( cd "$JJ" && jj log -r '@' --no-graph -T 'change_id' 2>/dev/null )"
[ "$id_before" = "$id_after" ] || fail "NO_CHECKPOINT=1 なのに @ が変わった（checkpoint が走った）"
echo "✅ C3) FLYWHEEL_NO_CHECKPOINT=1 で無効化（@ 不変）"

# --- C4) checkpoint 後、次 goal の baseline（fw_baseline_rev=@-）が確定 change を指す（連鎖整合）---
# loop-driver は checkpoint 直後に next→fw_init で baseline=@- を捕捉する。@- が確定した goal change を
# 指せば、次 goal の diff baseline が checkpoint 後にズレない（監視 council の統合懸念を helper 層で検証）。
base="$( cd "$JJ" && bash -c 'source "'"$COMMON"'"; fw_baseline_rev' )"
[ -n "$base" ] || fail "checkpoint 後 fw_baseline_rev が空"
base_desc="$( cd "$JJ" && jj log -r "$base" --no-graph -T 'description.first_line()' 2>/dev/null )"
printf '%s' "$base_desc" | grep -q "chain checkpoint" || fail "次 goal の baseline が確定 change を指さない（desc=[$base_desc]）"
echo "✅ C4) checkpoint 後の baseline=@- が確定 change を指す（連鎖整合）"

echo "🎉 chain-checkpoint 全ケース PASS"
