#!/usr/bin/env bash
# agent model tiering（v0.8.40）: agents/*.md の frontmatter model が層別リストどおりかを機械 assert。
# 観測・偵察・レビュー専任（コードを書かない）= sonnet 固定 / 考える部分（要件・設計の生成）= inherit。
# リスト外の agent があれば fail ＝ 新 agent 追加時の指定忘れも CI が拾う。
# FR-51 gotcha-actor-routing と同型（grep-lib・positive control 実走込み）。
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/grep-lib.sh"   # fail/ok/$ROOT（副作用なし）

# 層別リスト（2026-07-09 確定。根拠は ROADMAP「agent model tiering」行と agents/capabilities.md の
# モデル選択表。変更するときは design 判断を経て両方も同時に更新すること）
SONNET="architecture-mapper code-explorer convention-scout critic debugger drift-observer market-researcher oss-scout pattern-observer researcher scout security-reviewer"
INHERIT="analyst designer"
EXEMPT="capabilities"   # spawn されない reference doc（model 行なし）

# frontmatter（1つ目と2つ目の --- の間）の model: 値のみ抽出（本文中の言及に誤反応しない）
frontmatter_model() {
  awk '/^---$/{c++; next} c==1 && /^model:/{print $2; exit}' "$1"
}

check_agents_dir() {  # $1 = agents dir。層別違反・リスト外を列挙して非ゼロ。
  local f name m bad=""
  for f in "$1"/*.md; do
    name="$(basename "$f" .md)"
    m="$(frontmatter_model "$f")"
    if [[ " $SONNET " == *" $name "* ]]; then
      [[ "$m" == "sonnet" ]] || bad+="$name: model=${m:-無し}（期待: sonnet＝観測・レビュー専任）"$'\n'
    elif [[ " $INHERIT " == *" $name "* ]]; then
      [[ "$m" == "inherit" ]] || bad+="$name: model=${m:-無し}（期待: inherit＝考える部分・強モデル継承）"$'\n'
    elif [[ " $EXEMPT " == *" $name "* ]]; then
      :
    else
      bad+="$name: 層別リスト外。このテストの SONNET（観測・偵察・レビュー専任）か INHERIT（考える部分）に追加せよ"$'\n'
    fi
  done
  [[ -z "$bad" ]] || { printf '%s' "$bad"; return 1; }
}

# vacuous-pass ガード: リストに載る全ファイルの実在を assert（rename で検査対象が消えるのを検知）
for name in $SONNET $INHERIT $EXEMPT; do
  [[ -f "$ROOT/agents/$name.md" ]] || fail "agents/$name.md が無い（rename/削除なら層別リストも更新せよ）"
done
ok "層別リストの全 agent ファイルが実在"

# positive control: 検査ロジックが実際に fire することを fixture で実走（self-graded 化防止）
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/agents"
printf -- '---\nname: drift-observer\nmodel: inherit\n---\n' > "$T/agents/drift-observer.md"   # 層別違反
printf -- '---\nname: newcomer\nmodel: sonnet\n---\n'       > "$T/agents/newcomer.md"          # リスト外
if out="$(check_agents_dir "$T/agents")"; then
  fail "positive control: 層別違反 fixture を検出できていない（検査が一度も fire しない）"
fi
[[ "$out" == *"drift-observer"* ]] || fail "positive control: 層別違反（sonnet 期待に inherit）を検出していない: $out"
[[ "$out" == *"newcomer"*       ]] || fail "positive control: リスト外 agent を検出していない: $out"
ok "positive control: 層別違反 + リスト外を検出して非ゼロ"

# 本体: 実リポの agents/ を検査
if out="$(check_agents_dir "$ROOT/agents")"; then
  ok "agent-model-tiering: agents/*.md の model 層別が設計どおり（sonnet 12 / inherit 2 / 対象外 1）"
else
  printf '%s\n' "$out"
  fail "agents/*.md の model 層別が設計と不一致（上記）。観測・レビュー専任は sonnet / 考える部分は inherit（plan 由来の判断変更なら層別リストを design 判断込みで更新）"
fi
