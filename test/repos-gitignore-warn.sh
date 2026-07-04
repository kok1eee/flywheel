#!/usr/bin/env bash
# sibling .gitignore 警告（FR-57）: flywheel repos 登録時、sibling が .flywheel を gitignore して
# いなければ stderr 警告（exit 0・登録は成功）を検証。chain-lib の隔離ハーネスで live state を汚さない。
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/chain-lib.sh"

setup_impl "true"

# expect_warn <sibling path> <case> <warn|nowarn>: repos 登録の exit 0 と警告有無を assert
expect_warn() {
  local err
  err="$("$FW" repos "$1" 2>&1 >/dev/null)" || fail "$2: repos 登録が非ゼロ"
  if [ "$3" = "warn" ]; then
    printf '%s' "$err" | grep -q "\.flywheel を除外していません" || fail "$2: gitignore 警告が出ていない: $err"
  else
    printf '%s' "$err" | grep -q "\.flywheel を除外していません" && fail "$2: 除外済みなのに警告が出た: $err"
  fi
}

# C1: .gitignore 無しの sibling → 警告付きで登録成功
SIB1="$(mk_git_repo sib1)"
expect_warn "$SIB1" C1 warn
[ "$(getf '.repos | length')" = "1" ] || fail "C1: 警告付きでも登録されるべき"
ok "C1: gitignore 未除外の sibling は警告付きで登録される"

# C2: .flywheel/（スラッシュ付き）を gitignore 済み → 無警告
SIB2="$(mk_git_repo sib2)"
echo ".flywheel/" > "$SIB2/.gitignore"
expect_warn "$SIB2" C2 nowarn
ok "C2: .flywheel/ 除外済みの sibling は無警告"

# C3: .flywheel（スラッシュ無し）でも無警告（^/?\.flywheel/?$ の許容演習）
SIB3="$(mk_git_repo sib3)"
echo ".flywheel" > "$SIB3/.gitignore"
expect_warn "$SIB3" C3 nowarn
ok "C3: .flywheel（スラッシュ無し）除外でも無警告"

# C4: /.flywheel/（root-anchor 変種・gitignore の一般記法）でも無警告
SIB4="$(mk_git_repo sib4)"
echo "/.flywheel/" > "$SIB4/.gitignore"
expect_warn "$SIB4" C4 nowarn
ok "C4: /.flywheel/（root-anchor）除外でも無警告"

# C5: 複数 sibling 同時登録で警告が該当 sibling にのみ帰属する（per-repo 判定の演習）
err="$("$FW" repos "$SIB1" "$SIB2" 2>&1 >/dev/null)" || fail "C5: 複数登録が非ゼロ"
printf '%s' "$err" | grep -q "sib1 の .gitignore" || fail "C5: 未除外 sib1 への警告が無い: $err"
printf '%s' "$err" | grep -q "sib2 の .gitignore" && fail "C5: 除外済み sib2 に警告が出た: $err"
[ "$(getf '.repos | length')" = "2" ] || fail "C5: 2 sibling が登録されるべき"
ok "C5: 混在登録でも警告は未除外 sibling にのみ帰属"

echo "🎉 repos-gitignore-warn 全ケース PASS"
