#!/usr/bin/env bash
# 検証: adopt/start/add の `!` 動的注入行が $ARGUMENTS を single-quote で包み、
# ASCII シェルメタ文字を含む args でも parse error しない（FR-40）。next.md は $ARGUMENTS 不使用で対象外。
# C1) 3コマンドの `!` 行が '$ARGUMENTS' 形（"$ARGUMENTS" を含まない）
# C2) idiom の機能検証: hostile 文字列を single-quote 形に流すと bash -n 通過 / double-quote 形だと落ちる
#     （= single-quote 化が parse error を防ぐ根拠。$ARGUMENTS はプリプロセッサが先に literal 置換するので
#       single-quote 内でもシェル展開は起きず、メタ文字はリテラル保護される）
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/grep-lib.sh"   # fail/ok/$ROOT（副作用なし）

# ---- C1: 3コマンドの `!` 行が single-quote 形 ----
for c in adopt start add; do
  f="$ROOT/commands/$c.md"
  [ -f "$f" ] || fail "C1: $f が無い"
  grep -qF "'\$ARGUMENTS'" "$f" || fail "C1: commands/$c.md が '\$ARGUMENTS'（single-quote）形でない"
  grep -qF '"$ARGUMENTS"'   "$f" && fail "C1: commands/$c.md にまだ \"\$ARGUMENTS\"（double-quote）が残っている"
  ok "C1) commands/$c.md: single-quote 形"
done

# ---- C2: idiom の機能検証（single-quote は守る / double-quote は壊れる）----
# 単一バッククォート＝double-quote 形を確実に parse error にする hostile（literal ' は含めない）
hostile='back`tick "dq" (paren) $var'
fixed=$(printf "[ -n '%s' ] && true" "$hostile")   # single-quote 包み（修正後の形）
old=$(printf '[ -n "%s" ] && true'   "$hostile")   # double-quote（修正前の形）

if ! bash -n <<<"$fixed" 2>/dev/null; then
  fail "C2a: single-quote 形が hostile args で parse 失敗（fix が無効）。line=$fixed"
fi
ok "C2a) single-quote 形は hostile args でも parse OK"

if bash -n <<<"$old" 2>/dev/null; then
  fail "C2b: double-quote 形が parse 通った＝hostile が効いていない（テスト不成立）。line=$old"
fi
ok "C2b) double-quote 形は parse 失敗（single-quote 化が必要な根拠を確認）"

echo "🎉 adopt-args-sanitize 全ケース PASS"
