#!/usr/bin/env bash
# flywheel 共通ライブラリ — state machine の読み書きを1箇所に集約。
# bin/flywheel と各 hook がこれを source する。state ロジックの単一の出所。
set -euo pipefail

# --- リポ root 検出（jj → git → cwd） ---
fw_repo_root() {
  local r
  if r=$(jj root 2>/dev/null); then printf '%s\n' "$r"; return; fi
  if r=$(git rev-parse --show-toplevel 2>/dev/null); then printf '%s\n' "$r"; return; fi
  pwd
}

FW_ROOT="$(fw_repo_root)"
FW_DIR="$FW_ROOT/.flywheel"
FW_STATE="$FW_DIR/state.json"
FW_BACKLOG="$FW_DIR/backlog.jsonl"

# プラグイン本体の root（common.sh は <plugin>/hooks/lib/common.sh）。FW_ROOT（作業対象リポ）とは別。
# set -u 下で BASH_SOURCE[0] 未設定の文脈でも落ちないようガード（hook は全セッションで発火するため）。
_fw_src="${BASH_SOURCE[0]:-}"
if [[ -n "$_fw_src" ]]; then
  FW_PLUGIN_ROOT="$(cd "$(dirname "$_fw_src")/../.." && pwd)"
else
  FW_PLUGIN_ROOT="$FW_ROOT"
fi
unset _fw_src

# 有効な phase（state machine のノード）
FW_PHASES="no-spec designing spec-ready implementing polish eval done"

fw_state_exists() { [[ -f "$FW_STATE" ]]; }

# state.json の jq クエリ。state が無ければ空を返す。
# 注意: `// empty` は使わない（jq の // は false も falsy 扱いで boolean false を握り潰す）。
# null（=未設定）のみ空に落とし、false はそのまま "false" を返す。
fw_get() {
  fw_state_exists || { printf '\n'; return; }
  jq -r "$1 | select(. != null)" "$FW_STATE" 2>/dev/null || printf '\n'
}

fw_phase() { fw_get '.phase'; }

# 文字列フィールドを設定
fw_set() {
  fw_state_exists || return 1
  local tmp; tmp="$(mktemp)"
  jq --arg k "$1" --arg v "$2" 'setpath([$k]; $v)' "$FW_STATE" > "$tmp" && mv "$tmp" "$FW_STATE"
}

# 数値フィールドを設定
fw_set_num() {
  fw_state_exists || return 1
  local tmp; tmp="$(mktemp)"
  jq --arg k "$1" --argjson v "$2" 'setpath([$k]; $v)' "$FW_STATE" > "$tmp" && mv "$tmp" "$FW_STATE"
}

# phase を遷移し history に記録（from/to/by/ts）。state を進めるのは常に hook。
fw_advance() {
  local to="$1" by="$2" from tmp
  fw_state_exists || return 1
  case " $FW_PHASES " in *" $to "*) ;; *) echo "fw_advance: invalid phase '$to'" >&2; return 1;; esac
  from="$(fw_phase)"
  [[ "$from" == "$to" ]] && return 0
  tmp="$(mktemp)"
  jq --arg to "$to" --arg from "$from" --arg by "$by" --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '.phase = $to | .history += [{ts:$ts, from:$from, to:$to, by:$by}]' \
    "$FW_STATE" > "$tmp" && mv "$tmp" "$FW_STATE"
}

# state を初期化（flywheel start）。goal を記録し designing から開始。
# polish: "true"/"false"（FR-11、実装後 eval 前に simplify を steer するか）
fw_init() {
  local goal="$1" eval_cmd="${2:-}" polish="${3:-true}"
  mkdir -p "$FW_DIR"
  jq -n --arg goal "$goal" --arg ec "$eval_cmd" --argjson polish "$polish" --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{phase:"designing", goal:$goal, design_path:"plan/design.md", eval_cmd:$ec, polish:$polish, veto_count:0,
      history:[{ts:$ts, from:"no-spec", to:"designing", by:"flywheel start"}]}' \
    > "$FW_STATE"
}

# validate-plan を解決。flywheel 同梱版を最優先（自己完結）。
#   1. プラグイン同梱 bin/validate-plan
#   2. $FLYWHEEL_VALIDATE_PLAN（明示 override）
#   3. (後方互換) o-m-cc plugin cache の最新版
# 見つかればパスを出力し 0、無ければ空で 1。
fw_find_validate_plan() {
  if [[ -x "$FW_PLUGIN_ROOT/bin/validate-plan" ]]; then
    printf '%s\n' "$FW_PLUGIN_ROOT/bin/validate-plan"; return 0
  fi
  if [[ -n "${FLYWHEEL_VALIDATE_PLAN:-}" && -x "${FLYWHEEL_VALIDATE_PLAN}" ]]; then
    printf '%s\n' "$FLYWHEEL_VALIDATE_PLAN"; return 0
  fi
  local cand
  cand="$(ls -1d "$HOME"/.claude/plugins/cache/*/o-m-cc/*/bin/validate-plan 2>/dev/null | sort -V | tail -1)"
  if [[ -n "$cand" && -x "$cand" ]]; then printf '%s\n' "$cand"; return 0; fi
  return 1
}

# 実装意図の Edit/Write か判定（v1: source への書き込みのみ。plan/ .flywheel/ docs/ *.md は許可）。
# 引数: file_path。実装意図なら 0、そうでなければ 1 を返す。
fw_is_impl_write() {
  local fp="$1"
  [[ -z "$fp" ]] && return 1
  # リポ root 相対に正規化
  fp="${fp#"$FW_ROOT"/}"
  case "$fp" in
    plan/*|.flywheel/*|docs/*) return 1 ;;   # 設計・状態・文書 → 許可
    *.md|*.markdown)           return 1 ;;   # markdown は許可（README 等）
    *)                         return 0 ;;   # それ以外（source）→ 実装意図
  esac
}

# 完了/放棄スペックを plan/archive/<ts>/ に退避（FR-12）。plan/*.md が無ければ no-op。
# state.json のスナップショットも一緒に残す。
fw_archive_plan() {
  local plandir="$FW_ROOT/plan"
  [[ -f "$plandir/design.md" || -f "$plandir/requirements.md" ]] || return 0
  local ts dest f
  ts="$(date -u +%Y%m%d-%H%M%S)"
  mkdir -p "$plandir/archive"
  dest="$(mktemp -d "$plandir/archive/${ts}-XXXXXX")"
  for f in requirements.md design.md; do
    [[ -f "$plandir/$f" ]] && mv "$plandir/$f" "$dest/"
  done
  [[ -f "$FW_STATE" ]] && cp "$FW_STATE" "$dest/state.json"
  printf '%s\n' "$dest"
}

# backlog（FR-13）の残件数。
fw_backlog_count() {
  [[ -f "$FW_BACKLOG" ]] && awk 'END{print NR+0}' "$FW_BACKLOG" || echo 0
}

# プロジェクトファイルから eval(test/lint/型)コマンドを自動検出（--eval 省略時に使う）。
# 見つからなければ空（loop は degrade で stop 許可）。
fw_detect_eval() {
  local r="$FW_ROOT" cmd=""
  if [[ -f "$r/pyproject.toml" || -f "$r/pytest.ini" || -f "$r/setup.cfg" ]]; then
    grep -qE 'ruff' "$r/pyproject.toml" 2>/dev/null && cmd="ruff check"
    if [[ -f "$r/pytest.ini" ]] || grep -q 'tool.pytest' "$r/pyproject.toml" 2>/dev/null || [[ -d "$r/tests" ]]; then
      cmd="${cmd:+$cmd && }pytest"
    fi
  elif [[ -f "$r/package.json" ]]; then
    grep -q '"typecheck"' "$r/package.json" 2>/dev/null && cmd="npm run typecheck"
    grep -q '"lint"' "$r/package.json" 2>/dev/null && cmd="${cmd:+$cmd && }npm run lint"
    grep -qE '"test"[[:space:]]*:' "$r/package.json" 2>/dev/null && cmd="${cmd:+$cmd && }npm test"
  elif [[ -f "$r/Cargo.toml" ]]; then
    cmd="cargo test"
  elif [[ -f "$r/go.mod" ]]; then
    cmd="go test ./..."
  fi
  printf '%s\n' "$cmd"
}

# --- hook 共通ヘルパー（重複排除） ---

# 全 hook の冒頭ガード。bypass(FLYWHEEL_OFF) か flywheel 非稼働なら呼び出し側を即終了させる。
# 使い方: fw_hook_guard || exit 0
fw_hook_guard() {
  [[ "${FLYWHEEL_OFF:-}" == "1" ]] && return 1
  fw_state_exists || return 1
  return 0
}

# PreToolUse/PostToolUse の入力 JSON から tool_name と file_path を1回の jq で抽出し
# FW_TOOL / FW_FP にセットする（フィールド毎に jq を fork しない）。
fw_parse_tool_input() {
  IFS=$'\t' read -r FW_TOOL FW_FP < <(
    printf '%s' "$1" | jq -r '[.tool_name // "", .tool_input.file_path // ""] | @tsv'
  ) || { FW_TOOL=""; FW_FP=""; }
}

# designing フェーズの「次の設計ステップ」を plan/ の artifact から判断して案内する（パイプライン統合）。
# deep-interview → discovery-council → design → grill を artifact の有無で steer する。
fw_designing_steer() {
  local pd="$FW_ROOT/plan"
  if [[ ! -f "$pd/requirements.md" ]]; then
    cat <<'EOF'
→ まだ要件がありません。要件を固めてください:
  /flywheel:deep-interview  （雑な構想を1問ずつ掘り下げ）
  → /flywheel:discovery-council （3視点で統合し plan/requirements.md を作成）
EOF
  elif [[ ! -f "$pd/design.md" ]]; then
    cat <<'EOF'
→ 要件はあります（plan/requirements.md）。次は設計:
  /flywheel:design  （plan/design.md を作成）
EOF
  else
    cat <<'EOF'
→ 設計があります（plan/design.md）。叩いて validate を通せば門が開きます:
  /flywheel:grill  （設計を1問ずつ詰問）→ design.md を更新すると validate-plan 自動実行 → 合格で実装ゲート解放
EOF
  fi
}

# phase 述語（phase の意味論を1箇所に集約。各 hook は case 文を持たない）。
fw_gate_closed() { case "$1" in no-spec|designing) return 0 ;; *) return 1 ;; esac; }   # 実装ブロック中
fw_work_active() { case "$1" in spec-ready|implementing|polish|eval) return 0 ;; *) return 1 ;; esac; }  # loop が回すべき作業中 phase
