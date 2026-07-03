#!/usr/bin/env bash
# hooks 配線ガード（FR-53）: hooks/hooks.json の配線不変条件と、無音で落ちる prompt-level 前提を CI で観測する。
# 2.1.191 のカンマ区切り matcher silent 失敗が示した「気づけない配線破れ」class への対処。
# design-gate（PreToolUse block）は配線が破れると fail-open（無音で設計ゲート消失）なので loud に落とす。
# 注: 検査対象は repo 側の破れのみ。host（Claude Code）側の hook 意味論変更による fail-open は
# 静的ガードでは観測できない（residual・ROADMAP FR-53 行参照）。
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/grep-lib.sh"   # fail/ok/$ROOT（副作用なし）

# check_wiring <plugin root>: <root>/hooks/hooks.json の配線を検査。違反を1行出力して return 1。
# 不変条件（緩めない）: valid JSON / command エントリ1件以上 / matcher にカンマ無し / 参照 script 実在。
# 規約（正当な配線変更なら更新してよい）: 全 command は `bash ${CLAUDE_PLUGIN_ROOT}/hooks/<name>.sh`。
check_wiring() {
  local root="$1" json="$1/hooks/hooks.json" cmds bad cmd f
  [ -f "$json" ] || { echo "hooks.json が無い: $json"; return 1; }
  jq empty "$json" 2>/dev/null || { echo "hooks.json が valid JSON でない"; return 1; }
  # command を1回だけ抽出し、0件ガードと実在検査が同じデータを見る（jq path の片更新乖離を構造的に防ぐ）
  cmds="$(jq -r '.hooks[][].hooks[].command' "$json" 2>/dev/null)" \
    || { echo "hooks 構造が想定外（.hooks.<Event>[].hooks[].command が辿れない）"; return 1; }
  [ -n "$cmds" ] || { echo "command エントリが 0 件"; return 1; }
  # matcher にカンマ禁止（pipe 区切りが正・2.1.191 の silent 失敗 class）
  bad="$(jq -r '.hooks[][] | select(.matcher // "" | contains(",")) | .matcher' "$json" 2>/dev/null)" \
    || { echo "matcher 検査の jq が失敗（matcher が非文字列?）"; return 1; }
  [ -z "$bad" ] || { echo "カンマ区切り matcher（pipe が正）: $bad"; return 1; }
  # 参照 script の実在（${CLAUDE_PLUGIN_ROOT} は literal 文字列なので root に読み替えて検査）
  while IFS= read -r cmd; do
    case "$cmd" in
      "bash \${CLAUDE_PLUGIN_ROOT}/hooks/"*.sh) ;;
      *) echo "配線規約外の command: $cmd"; return 1 ;;
    esac
    f="$root/hooks/${cmd##*/hooks/}"
    [ -f "$f" ] || { echo "参照 script が実在しない: $f"; return 1; }
  done <<< "$cmds"
}

# --- 検査ロジックの自己検証: 壊れた fixture を検出できること（失敗パスの実走・FR-51 と同型） ---
# expect_broken <dir> <期待メッセージ断片> <ラベル>: check_wiring が非ゼロ + 期待した理由で落ちることを assert
# （非ゼロだけだと「別のチェックが誤爆して落ちた」でも通ってしまう）。
expect_broken() {
  local out
  if out="$(check_wiring "$1" 2>&1)"; then
    fail "positive control($3): 検出できていない（lint が fire しない）"
  fi
  [[ "$out" == *"$2"* ]] || fail "positive control($3): 期待した理由で落ちていない: $out"
  ok "positive control: $3 を検出"
}
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/comma/hooks" "$T/ghost/hooks" "$T/missing/hooks" "$T/zero/hooks"

cat > "$T/comma/hooks/hooks.json" <<'EOF'
{"hooks":{"PreToolUse":[{"matcher":"Bash,PowerShell","hooks":[{"type":"command","command":"bash ${CLAUDE_PLUGIN_ROOT}/hooks/x.sh"}]}]}}
EOF
touch "$T/comma/hooks/x.sh"
expect_broken "$T/comma" "カンマ区切り matcher" "カンマ区切り matcher"

cat > "$T/ghost/hooks/hooks.json" <<'EOF'
{"hooks":{"Stop":[{"matcher":"","hooks":[{"type":"command","command":"bash ${CLAUDE_PLUGIN_ROOT}/hooks/ghost.sh"}]}]}}
EOF
expect_broken "$T/ghost" "実在しない" "実在しない script 参照"

expect_broken "$T/missing" "hooks.json が無い" "hooks.json 消失"   # hooks/ のみで json 無し

echo '{"hooks":{}}' > "$T/zero/hooks/hooks.json"
expect_broken "$T/zero" "0 件" "command エントリ 0 件"

# --- 本番検査: 現リポの配線が全 assert green ---
if out="$(check_wiring "$ROOT")"; then
  ok "hooks-wiring: hooks.json の配線 OK（valid JSON / 全 script 実在 / カンマ matcher なし）"
else
  printf '%s\n' "$out"
  fail "hooks.json の配線が破れている（fail-open で無音化する前に直す）"
fi

# --- prompt-level 前提のガード: council 同期 spawn 指示の消失検知（同じ「無音で落ちる前提」class） ---
# monitor SKILL.md は evolve が定常的に書き換えるファイルで、sync 指示が落ちても run-all は緑のまま
# （regression の検知は council 1 周を無駄にした後になる）。指示の存在を grep で観測する。
# anchor: Step 2 の spawn 指示行（subagent_type と同一行）に限定。裸の 'run_in_background: false' だと
# Gotcha 113 追記の言及にもマッチし、肝心の指示が消えても緑のままになる（FR-53 council 指摘）。
n_sync="$(grep -c 'subagent_type: "flywheel:drift-observer".*run_in_background: false' "$ROOT/skills/monitor/SKILL.md")" || true
[ "${n_sync:-0}" -eq 1 ] \
  || fail "monitor SKILL.md の spawn 指示 anchor が一意でない（${n_sync:-0} 行）: 0=指示消失（2.1.198+ で council が構造的に空振り）/ 2+=完全引用の混入で消失検知が無効化される"
ok "monitor SKILL.md の観測者 sync spawn 指示が存在（spawn 行 anchor・一意）"

# FR-55 council: agents/ に旧 opt-in 背景 frontmatter が再混入しないこと（binding 用途と矛盾する 2.1.196 以前の遺物）
! grep -rq '^background: true' "$ROOT/agents/" \
  || fail "agents/*.md に background: true が再混入: $(grep -rln '^background: true' "$ROOT/agents/" | tr '\n' ' ')"
ok "agents/ に background: true の残骸なし"

# FR-55: 他の binding fan-out 面にも sync 指示の存在を assert（≥1）
for f in "skills/design/SKILL.md" "skills/verification/SKILL.md" "agents/researcher.md" "agents/analyst.md" "agents/scout.md"; do
  grep -q 'run_in_background: false' "$ROOT/$f" \
    || fail "$f から binding fan-out の sync 指示（run_in_background: false）が消えた（2.1.198+ で集約が空振りする）"
done
# reference.md はテンプレ複数のため「全テンプレに sync がある」を self-adjusting に assert
# （sync 数 == subagent_type 数。テンプレ追加には自動追従し、一部テンプレだけの無音消失を検知）
REF="$ROOT/skills/discovery-council/reference.md"
n_tpl="$(grep -c 'subagent_type:' "$REF")" || true
n_syn="$(grep -c 'run_in_background: false' "$REF")" || true
[ "${n_tpl:-0}" -ge 1 ] && [ "${n_syn:-0}" -eq "${n_tpl:-0}" ] \
  || fail "discovery-council/reference.md の sync 指示がテンプレ数と不一致（templates=$n_tpl sync=$n_syn）: 一部テンプレから消えても他が残ると ≥1 assert では素通りする"
ok "binding fan-out 3 面（discovery-council 全テンプレ / design / verification）の sync 指示が存在"
