#!/usr/bin/env bash
# ultrawork（v0.8.43）: 全 Fable judge panel skill の構造アサート。
# 核の不変条件「SKILL.md 内の全 agent 呼び出しが model: 'fable' 指定」を機械観測する
# （silent に崩れると『メインのモデルに関係なく常に Fable 品質』の保証が消える）。
# 実際に Workflow/Agent を動かす実行テストは高コスト・非決定論のため対象外（design 判断）。
# FR-51 gotcha-actor-routing と同型（grep-lib・positive control 実走込み）。
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/grep-lib.sh"   # fail/ok/$ROOT（副作用なし）

SKILL="$ROOT/skills/ultrawork/SKILL.md"
CMD="$ROOT/commands/ultrawork.md"

# 全 Fable 不変条件の検査関数（$1=SKILL.md path）:
#   agent( の出現数 == model: 'fable' の出現数（1つでも指定漏れ＝inherit 落ちで fail）
#   かつ fable 以外のモデル指定（sonnet/haiku/opus）が混入していない。
# 注意: 集計一致でありペア照合ではない（指定漏れ+コメント内の紛れ込みが相殺すると素通りする。
# SKILL.md 編集時は数だけ信じず diff を目視する契約＝SKILL.md Gotchas にも明記）。
check_all_fable() {
  local f="$1" n_agent n_fable
  n_agent="$(grep -o "agent(" "$f" | wc -l)"
  n_fable="$(grep -o "model: 'fable'" "$f" | wc -l)"
  [[ "$n_agent" -gt 0 ]] || { echo "agent 呼び出しが1つも無い（$f）"; return 1; }
  [[ "$n_agent" -eq "$n_fable" ]] \
    || { echo "agent( が ${n_agent} 件に対し model: 'fable' が ${n_fable} 件（全 Fable 不変条件が崩れている）"; return 1; }
  if grep -qE "model: '(sonnet|haiku|opus)'" "$f"; then
    echo "fable 以外のモデル指定が混入している"; return 1
  fi
  return 0
}

# ---- 実ファイルの構造 assert ----
[[ -f "$SKILL" ]] || fail "skills/ultrawork/SKILL.md が無い"
grep -q '^name: ultrawork$' "$SKILL"        || fail "frontmatter に name: ultrawork が無い"
grep -q '^description:' "$SKILL"            || fail "frontmatter に description が無い"
grep -q '^allowed-tools:.*Workflow' "$SKILL" || fail "frontmatter の allowed-tools に Workflow が無い"
ok "SKILL.md の存在 + frontmatter（name / description / allowed-tools に Workflow）"

# 高コスト明示（自発起動禁止の契約が description から消えたら fail）
grep -q '「ultrawork」と明示' "$SKILL" || fail "description から明示トリガー限定（「ultrawork」と明示）の契約が消えている"
ok "description に高コスト・明示トリガー限定の契約がある"

[[ -f "$CMD" ]] || fail "commands/ultrawork.md が無い"
grep -q '^description:' "$CMD" || fail "commands/ultrawork.md の frontmatter に description が無い"
ok "commands/ultrawork.md の存在 + description"

# ---- positive control（FR-51 前例・検査が一度も fire しない self-graded 化を防ぐ）----
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

# fixture 1: fable 指定の欠落（inherit 落ち）
cat > "$T/bad1.md" <<'EOF'
const x = await agent(`prompt`, { label: 'no-model' })
const y = await agent(`prompt`, { model: 'fable' })
EOF
if out="$(check_all_fable "$T/bad1.md")"; then
  fail "positive control: fable 指定漏れを検出できていない"
fi
[[ "$out" == *"全 Fable 不変条件"* ]] || fail "positive control: 件数不一致の理由が出力されていない: $out"
ok "positive control: fable 指定漏れ（inherit 落ち）を検出して非ゼロ"

# fixture 2: 件数は揃っているが他モデルが混入
cat > "$T/bad2.md" <<'EOF'
await agent(`p`, { model: 'fable' })
await agent(`p`, { model: 'fable' })
const helper = { model: 'sonnet' }
EOF
if out="$(check_all_fable "$T/bad2.md")"; then
  fail "positive control: 他モデル混入を検出できていない"
fi
[[ "$out" == *"混入"* ]] || fail "positive control: 混入の理由が出力されていない: $out"
ok "positive control: fable 以外のモデル混入を検出して非ゼロ"

# ---- 本体: 実 SKILL.md の全 Fable 不変条件 ----
if out="$(check_all_fable "$SKILL")"; then
  ok "ultrawork-skill: SKILL.md の全 agent 呼び出しが model: 'fable' 指定（混入なし）"
else
  printf '%s\n' "$out"
  fail "SKILL.md の全 Fable 不変条件が崩れている（agent 呼び出しを足すときは model: 'fable' を明示する）"
fi

echo "🎉 ultrawork-skill 全ケース PASS"
