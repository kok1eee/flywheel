#!/usr/bin/env bash
# evolve actor-routing の機械検査（FR-51）: skills/*/SKILL.md の AUTO-GOTCHAS 配下に
# fan-out agent 向け Gotcha（bullet title が actor 主語で始まる＝誤配送）が居たら fail する恒久ガード。
# 実例: 観測者レンズ2件が monitor SKILL.md に誤配送され、観測者（agents/drift-observer.md を
# system prompt として読む）に届かないまま数日生存した（2026-07-02 に移設）。evolve Step 2.7 の
# prompt-level 規則の機械化。grep ベース（runtime smoke 対象なし）なので grep-lib.sh を source。
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/grep-lib.sh"   # fail/ok/$ROOT（副作用なし）

# fan-out agent 向けの actor 主語（誤配送の実例 class のみ。agent が増えたら | 区切りで足す。
# evolve Step 2.7 の routing 表と対で保守。動的 regex に埋めるためメタ文字は不可＝日本語主語では実質無関係）
SUBJECTS='観測者は|reviewer は'

# check_skills_dir <dir>: <dir>/*/SKILL.md の AUTO-GOTCHAS マーカーより下から、auto 追記定型
# `- **[日付] title**` の title が actor 主語で始まる行を探す。ヒットを file:line: 内容 で出力し
# return 1。本文中の言及・マーカーより上（手動 Gotchas）は不問（false positive ゼロ設計）。
check_skills_dir() {
  local out
  out="$(awk -v subjects="$SUBJECTS" '
    FNR == 1 { in_auto = 0 }
    /<!-- AUTO-GOTCHAS -->/ { in_auto = 1; next }
    in_auto && $0 ~ ("^- \\*\\*\\[[^]]*\\] (" subjects ")") { print FILENAME ":" FNR ": " $0 }
  ' "$1"/*/SKILL.md 2>/dev/null)"
  [[ -z "$out" ]] || { printf '%s\n' "$out"; return 1; }
}

# --- 検査対象消失・形式 drift の false-pass ガード（intent-router-removed の学びと同型） ---
ls "$ROOT"/skills/*/SKILL.md >/dev/null 2>&1 || fail "skills/*/SKILL.md が1つも無い（skills/ 消失含む・検査対象消失で false-pass し得る）"
grep -q -- '<!-- AUTO-GOTCHAS -->' "$ROOT"/skills/*/SKILL.md || fail "AUTO-GOTCHAS マーカーが skills/ に1つも無い（evolve の追記形式が drift? 検査が vacuous pass し得る）"

# --- 1) 検査ロジックの自己検証: 誤配送 fixture を検出できること（失敗パスの実走） ---
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/hit/monitor" "$T/clean/monitor"
cat > "$T/hit/monitor/SKILL.md" <<'EOF'
## Gotchas

<!-- AUTO-GOTCHAS -->
- **[2026-07-01] 観測者は境界値を必ず突く**: 誤配送の再現（fan-out agent 向け title が skill 側に居る）。
EOF
if out="$(check_skills_dir "$T/hit")"; then
  fail "positive control: 誤配送 fixture を検出できていない（lint が一度も fire しない）"
fi
[[ "$out" == *"SKILL.md:4:"* ]] || fail "positive control: 検出出力に file:line が無い: $out"
ok "positive control: 誤配送 Gotcha を検出して非ゼロ + file:line 出力"

# --- 2) false positive ガード: マーカーより上の同文・本文中の言及は検出しないこと ---
cat > "$T/clean/monitor/SKILL.md" <<'EOF'
## Gotchas

- **観測者の「drift なし」を鵜呑みにする**: overseer 向け手動項（観測者に言及するが不問）。
- **[2026-07-01] 観測者は境界値を必ず突く**: マーカーより上に居る同文（不問）。

<!-- AUTO-GOTCHAS -->
- **[2026-06-15] forked 実行が空振りする**: 本文で観測者 fan-out に言及するが title 主語ではない（不問）。
EOF
check_skills_dir "$T/clean" >/dev/null \
  || fail "false positive: マーカーより上 / 本文中言及を誤検知した"
ok "false positive ガード: マーカーより上・title 主語でない言及は検出しない"

# --- 3) 本番検査: 現リポの skills/ に誤配送が無いこと ---
if out="$(check_skills_dir "$ROOT/skills")"; then
  ok "gotcha-actor-routing: skills/*/SKILL.md の AUTO-GOTCHAS に fan-out agent 向け Gotcha なし"
else
  printf '%s\n' "$out"
  fail "AUTO-GOTCHAS に fan-out agent 向け Gotcha（誤配送）。agents/<name>.md の AUTO-GOTCHAS へ移設する（evolve Step 2.7）"
fi
