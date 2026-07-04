#!/usr/bin/env bash
# 共有テストハーネス: adopt-chain.sh / start-chain.sh が source する。
# loop-driver の done→連鎖を、live state を壊さない mktemp -d の使い捨て git リポで検証するための
# 足場（環境分離・state 操作ヘルパ・done 直前 state の整形）。source した時点でカレントが使い捨て
# リポ（$REPO_T）に移る。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
FW="$REPO/bin/flywheel"
HOOK="$REPO/hooks/loop-driver.sh"

fail() { echo "❌ FAIL: $1"; exit 1; }
ok()   { echo "✅ $1"; }

TMP="$(mktemp -d)"; trap 'chmod -R u+w "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT   # u+w 前置: read-only 演習中の fail でも掃除が失敗しない（FR-56）
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

# jq_patch <file> <jq-args...>: JSON ファイルへの「jq → tmp → mv」上書きの共有形（FR-56）。
# 例: jq_patch "$s" '.phase="eval"' / jq_patch "$s" --arg p "$p" '.phase=$p'
jq_patch() { local f="$1"; shift; jq "$@" "$f" > "$f.tmp" && mv "$f.tmp" "$f"; }

# mk_git_repo <name>: $TMP/<name> に使い捨て git リポ（seed 1 commit）を作り絶対 path を echo（FR-57）。
# REPO_T 初期化・multirepo 系 fixture と同型のボイラープレートの共有形。
mk_git_repo() {
  local d="$TMP/$1"
  mkdir -p "$d"
  ( cd "$d" && git init -q && git config user.email t@example.com && git config user.name tester \
    && echo seed > seed.txt && git add -A && git commit -qm init ) || fail "git リポ初期化失敗: $1"
  echo "$d"
}

# 任意 eval_cmd で「実装中（eval が走る）」状態を作る素地。fresh start なので veto=0。
setup_impl() {  # $1 = eval_cmd
  rm -rf "$REPO_T/.flywheel" "$REPO_T/plan"
  "$FW" start "goal A" --eval "$1" >/dev/null 2>&1 || fail "flywheel start 失敗"
  jq_patch "$(state)" '.phase="implementing" | .eval_src="explicit" | .polish=false | .polished=true' \
    || fail "state 整形失敗"
}

# goal A を done 直前の姿（implementing + eval 緑(true) + monitor clean）に整える＝setup_impl の特化。
setup_done_ready() {
  setup_impl "true"
  jq_patch "$(state)" '.monitor={status:"clean"}' || fail "monitor 整形失敗"
}

run_hook() { FLYWHEEL_HOOK=1 bash "$HOOK" </dev/null >/dev/null 2>&1; echo $?; }

# with_readonly <path> <mode> <cmd...>: path を <mode> に chmod して cmd を実行し、元の mode に
# 復元してから cmd の exit code を返す（observation-only の write 失敗演習・FR-56 rule-of-three）。
# fail() 中断などの異常系は上の EXIT trap（chmod -R u+w → rm -rf）が拾う二段構え。
# 契約注意: stat/chmod の前置に失敗したら cmd を実行せず rc=1（「必ず cmd が走る」とは仮定しないこと）。
with_readonly() {
  local path="$1" mode="$2" orig rc=0; shift 2
  orig="$(stat -c %a "$path")" || return 1
  chmod "$mode" "$path" || return 1
  "$@" || rc=$?
  chmod "$orig" "$path"
  return "$rc"
}
