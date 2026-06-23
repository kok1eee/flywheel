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

# ユーザー/モデル向けメッセージで CLI を案内する表記。PATH にあれば短く、
# 無ければ plugin 同梱の実体パス（plugin install だけで全ディレクトリ動作させる）。
if command -v flywheel >/dev/null 2>&1; then FW_CLI="flywheel"; else FW_CLI="$FW_PLUGIN_ROOT/bin/flywheel"; fi

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

# 数値/真偽値フィールドを設定（値は JSON リテラルとして渡す）
fw_set_json() {
  fw_state_exists || return 1
  local tmp; tmp="$(mktemp)"
  jq --arg k "$1" --argjson v "$2" 'setpath([$k]; $v)' "$FW_STATE" > "$tmp" && mv "$tmp" "$FW_STATE"
}

# 文字列フィールドを設定
fw_set_str() {
  fw_state_exists || return 1
  local tmp; tmp="$(mktemp)"
  jq --arg k "$1" --arg v "$2" 'setpath([$k]; $v)' "$FW_STATE" > "$tmp" && mv "$tmp" "$FW_STATE"
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

# goal 開始時点の基準 revision（FR-20: goal の累積 diff の起点）。<dir> の per-repo 版。
# jj: @ の親（運用ルール上 start 前に `jj new` するので @ は空 = 親が開始時点。
#     @ 自身の commit_id は snapshot ごとに変わるため使えない）
# git: HEAD。どちらも無ければ空（degrade）。cwd を <dir> に変えて jj→git→空を試すので
# VCS 種別は各リポで自動検出される（FR-A マルチレポ: 宣言した sibling repo の baseline 捕捉に使う）。
fw_repo_baseline() {
  local dir="$1" r
  if r=$(cd "$dir" && jj log -r '@-' --no-graph -T 'commit_id ++ "\n"' 2>/dev/null | head -1) && [[ -n "$r" ]]; then
    printf '%s\n' "$r"; return
  fi
  if r=$(cd "$dir" && git rev-parse HEAD 2>/dev/null); then printf '%s\n' "$r"; return; fi
  printf '\n'
}
fw_baseline_rev() { fw_repo_baseline "$FW_ROOT"; }   # FW_ROOT 用（従来の呼び出し元はそのまま）

# repos の path（FW_ROOT 相対 or 絶対）を実ディレクトリへ解決（FR-A/B 共通。setter と diff で規約を1箇所に）。
fw_repo_dir() { case "$1" in /*) printf '%s\n' "$1" ;; *) printf '%s\n' "$FW_ROOT/$1" ;; esac; }

# <root> の <base> からの累積「実装」変更行数（FR-B マルチレポの per-repo コア）。
# 従来の fw_goal_diff_lines を root 引数化しただけ:
# - 累積: 途中で commit / push しても測れる（working copy だけだと commit ごとにゼロリセット）
# - 実装のみ: per-file stat 行を fw_is_impl_write でフィルタ（.flywheel//plan//docs//*.md を除外）。
#   diff --stat の出力パスは各リポ root 相対なので、sibling でも各リポ root 相対で判定される（FR ④）
# - pure git は未 track 新規が diff --stat に乗らないため別途加算（jj は snapshot 済みで不要）
# base 空・root 不在・diff 取得失敗は 0。
fw_repo_diff_lines() {
  local root="$1" base="$2" out f n total=0
  [[ -z "$base" || ! -d "$root" ]] && { printf '0\n'; return; }
  if ! out=$(cd "$root" && jj diff --from "$base" --stat 2>/dev/null); then
    # -M(--find-renames): rename を1エントリ（変更行のみ）に collapse。diff.renames config に依存
    # せず純粋 rename を 0 行扱いにし、無意味な polish 発火を防ぐ（jj path は既定で rename 検出）。
    # -C(copy) は足さない: コピー＝重複＝simplify が拾うべき対象なので skip させない。
    out=$(cd "$root" && git diff -M --stat "$base" 2>/dev/null) || { printf '0\n'; return; }
    while IFS= read -r f; do
      fw_is_impl_write "$f" || continue
      n=$(wc -l < "$root/$f" 2>/dev/null) || n=0
      total=$((total + n))
    done < <(cd "$root" && git ls-files --others --exclude-standard 2>/dev/null)
  fi
  while IFS='|' read -r f n; do
    [[ -z "$n" ]] && continue
    f="${f#"${f%%[![:space:]]*}"}"; f="${f%"${f##*[![:space:]]}"}"   # 前後の空白を trim
    fw_is_impl_write "$f" || continue
    n="${n//[^0-9]/}"
    total=$((total + ${n:-0}))
  done <<< "$out"
  printf '%s\n' "$total"
}

# baseline からの累積「実装」変更行数を出力（FR-20）。FW_ROOT + 宣言された sibling repo（FR-B）を合算。
# FW_ROOT の baseline 無しは空で degrade（呼び出し側が常に polish 判断）。
# sibling は baseline ごと state.repos が持つ（path は FW_ROOT 相対 or 絶対）。
fw_goal_diff_lines() {
  local base total n p b
  base="$(fw_get '.baseline_rev')"
  [[ -z "$base" ]] && { printf '\n'; return; }
  total="$(fw_repo_diff_lines "$FW_ROOT" "$base")"
  while IFS=$'\t' read -r p b; do
    [[ -z "$p" ]] && continue
    n="$(fw_repo_diff_lines "$(fw_repo_dir "$p")" "$b")"
    total=$((total + ${n:-0}))
  done < <(jq -r '(.repos // [])[] | [.path, .baseline] | @tsv' "$FW_STATE" 2>/dev/null)
  printf '%s\n' "$total"
}

# done→chain 境界の checkpoint commit message を goal から生成（FR-46・repo 非依存）。
fw_checkpoint_msg() {
  # 1行目を文字単位で72字に切る。`cut -c` はロケール次第で UTF-8 をバイト切断し日本語を壊すため、
  # bash 部分文字列（UTF-8 ロケールで文字単位）を使う＝リポの `${var:0:N}` UTF-8 規約に揃える。
  local first
  first="$(printf '%s' "$1" | head -1)"
  printf 'chore: chain checkpoint — %s\n' "${first:0:72}"
}

# chain 連鎖（done→next）の境界で、完了 goal を独立 change に確定して履歴粒度を保つ（FR-46）。
# jj のみ: describe(@＝完了 goal をラベル) + new(N+1 用の空 change)。git は degrade（surprise commit しない）。
# best-effort: 失敗しても loop を止めない（return 0）。hook が VCS 操作する＝C-2（モデル≠state）不変。
# 呼び出しは loop-driver の done→chain 境界のみ（file 編集が止まる安全なタイミング）。
fw_chain_checkpoint() {
  [[ "${FLYWHEEL_NO_CHECKPOINT:-}" == "1" ]] && return 0
  if ! ( cd "$FW_ROOT" && jj root >/dev/null 2>&1 ); then
    echo "ℹ️ flywheel: chain checkpoint は jj リポのみ（git は skip）。" >&2
    return 0
  fi
  local msg; msg="$(fw_checkpoint_msg "$(fw_get '.goal')")"
  ( cd "$FW_ROOT" && jj describe -m "$msg" >/dev/null 2>&1 ) \
    || { echo "⚠️ flywheel: chain checkpoint の describe 失敗（skip）。" >&2; return 0; }
  ( cd "$FW_ROOT" && jj new >/dev/null 2>&1 ) \
    || { echo "⚠️ flywheel: chain checkpoint の jj new 失敗（skip）。" >&2; return 0; }
  echo "🔖 flywheel: chain checkpoint — 完了 goal を確定し新 change を切りました（$msg）。" >&2
}

# state を初期化（flywheel start / adopt）。goal を記録し designing から開始。
# polish: "true"/"false"（FR-11、実装後 eval 前に simplify を steer するか）
# eval_src: eval_cmd の出所 "explicit"（--eval 明示）/ "auto"（自動検出）/ ""（なし）。
#   explicit 以外は design-validator が spec の完了条件で上書きできる（FR-19）。
# entry: designing への入り方 "start"（要件を掘る）/ "adopt"（会話/handoff 合意を結晶化・FR-29）。
#   fw_designing_steer がこの値で steer を分岐する。
fw_init() {
  local goal="$1" eval_cmd="${2:-}" polish="${3:-true}" eval_src="${4:-}" entry="${5:-start}" notes="${6:-}"
  mkdir -p "$FW_DIR"
  # notes: /add の軽量 grill で詰めた Boundary/曖昧点（next 起動時に backlog entry から引き継ぐ design の種）。
  jq -n --arg goal "$goal" --arg ec "$eval_cmd" --argjson polish "$polish" --arg src "$eval_src" \
    --arg entry "$entry" --arg notes "$notes" \
    --arg base "$(fw_baseline_rev)" --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{phase:"designing", goal:$goal, design_path:"plan/design.md", eval_cmd:$ec, eval_src:$src, polish:$polish, polished:false, veto_count:0,
      entry:$entry, notes:$notes, baseline_rev:$base, watch_focus:"", monitor:null, monitor_attempts:0,
      history:[{ts:$ts, from:"no-spec", to:"designing", by:("flywheel " + $entry)}]}' \
    > "$FW_STATE"
  # FR-31: goal-start を全 start 経路で計測（観測漏れ防止）。fw_init は CLI start/next/adopt・
  # plan route(plan-approved) すべての共通 chokepoint。
  # 経路は手元の signal から導出: plan route は eval_src=spec / adopt は entry=adopt / 他は start。
  local route="$entry"
  [[ "$eval_src" == "spec" ]] && route="plan"
  fw_log_usage "goal:$route"
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
    /*)                        return 1 ;;   # FW_ROOT 外（/tmp 等。prefix が剥けず絶対パスのまま）→ 調査スクラッチとして許可
    plan/*|.flywheel/*|docs/*) return 1 ;;   # 設計・状態・文書 → 許可
    *.md|*.markdown)           return 1 ;;   # markdown は許可（README 等）
    *)                         return 0 ;;   # それ以外（リポ内 source）→ 実装意図
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
  local r="$FW_ROOT" cmd="" run=""
  # uv プロジェクト（uv.lock or [tool.uv]）なら python ツールを uv run 経由にする。
  # loop-driver は PATH に mise shims しか前置しないため、.venv にしか無い pytest/ruff を
  # 直呼びすると command not found になり eval が空振りする（uv プロジェクトでの dogfood で観測）。
  if [[ -f "$r/uv.lock" ]] || grep -q '^\[tool\.uv\]' "$r/pyproject.toml" 2>/dev/null; then
    run="uv run "
  fi
  if [[ -f "$r/pyproject.toml" || -f "$r/pytest.ini" || -f "$r/setup.cfg" ]]; then
    grep -qE 'ruff' "$r/pyproject.toml" 2>/dev/null && cmd="${run}ruff check"
    if [[ -f "$r/pytest.ini" ]] || grep -q 'tool.pytest' "$r/pyproject.toml" 2>/dev/null || [[ -d "$r/tests" ]]; then
      cmd="${cmd:+$cmd && }${run}pytest"
    fi
  elif [[ -f "$r/package.json" ]]; then
    # JS ランナーを lockfile から判定（bun/pnpm/yarn、無ければ npm）。npm 直叩きだと
    # bun プロジェクトで script が解決できない（uv と同じクラスのバグ）。
    local js="npm run"
    if [[ -f "$r/bun.lockb" || -f "$r/bun.lock" ]]; then js="bun run"
    elif [[ -f "$r/pnpm-lock.yaml" ]]; then js="pnpm run"
    elif [[ -f "$r/yarn.lock" ]]; then js="yarn run"
    fi
    grep -q '"typecheck"' "$r/package.json" 2>/dev/null && cmd="$js typecheck"
    grep -q '"lint"' "$r/package.json" 2>/dev/null && cmd="${cmd:+$cmd && }$js lint"
    grep -qE '"test"[[:space:]]*:' "$r/package.json" 2>/dev/null && cmd="${cmd:+$cmd && }$js test"
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

# PreToolUse/PostToolUse の入力 JSON から tool_name と file_path（NotebookEdit は
# notebook_path）を1回の jq で抽出し FW_TOOL / FW_FP にセットする（フィールド毎に fork しない）。
fw_parse_tool_input() {
  IFS=$'\t' read -r FW_TOOL FW_FP < <(
    printf '%s' "$1" | jq -r '[.tool_name // "", .tool_input.file_path // .tool_input.notebook_path // ""] | @tsv'
  ) || { FW_TOOL=""; FW_FP=""; }
}

# designing フェーズの「次の設計ステップ」を plan/ の artifact から判断して案内する（パイプライン統合）。
# deep-interview → discovery-council → design → grill を artifact の有無で steer する。
# entry=="adopt"（FR-29）かつ design.md 未作成なら「掘る」をスキップし結晶化を steer する。
fw_designing_steer() {
  local pd="$FW_ROOT/plan"
  if [[ "$(fw_get '.entry')" == "adopt" && ! -f "$pd/design.md" ]]; then
    cat <<'EOF'
→ adopt: 会話で合意した実装方針（無ければ .claude/journal.md 先頭エントリの Next Actions）を
  plan/design.md に結晶化してください。「## 完了条件（eval）」セクションも必ず設計してください
  （done を機械判定する fenced command）。掘り直し（deep-interview/discovery-council）は不要です。
  → design.md を書くと validate-plan が自動実行され、合格で実装ゲートが開きます。
EOF
    return
  fi
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

# 計画/設計テキスト（stdin）の「## 完了条件（eval）」セクションから実行コマンドを抽出（FR-19/21）。
# セクション内の最初の fenced code block を読み、空行と # コメント行を除いて && で連結
# （1行 = 1コマンド規約。連結により途中失敗で即 fail する）。見出しは 完了条件 / 受け入れ基準 を許容。
# セクション or block が無ければ空。
fw_extract_spec_eval_text() {
  awk '
    /^#{2,3} / { insec = ($0 ~ /完了条件|受け入れ基準/) ; next }
    insec && /^```/ { if (inblock) exit; inblock = 1; next }
    inblock && !/^[[:space:]]*(#|$)/ { lines = lines (lines ? " && " : "") $0 }
    END { print lines }
  '
}

# 同上の design.md ファイル版（無ければ空 = degrade: eval_cmd は従来の解決順のまま）。
fw_extract_spec_eval() {
  local f="$FW_ROOT/plan/design.md"
  [[ -f "$f" ]] || { printf '\n'; return; }
  fw_extract_spec_eval_text < "$f"
}

# eval 出力（stdin）から fail 数を best-effort 抽出する（FR-25）。
# 対応: pytest/jest「N failed」、ruff「Found N errors」、ty「Found N diagnostics」、go「--- FAIL:」行数。
# eval_cmd は && 連鎖で最初に落ちたツールの出力だけが出るので、複数パターンは合算で安全。
# どのパターンにも合わなければ空（呼び出し側は方向表示なしに degrade）。
fw_count_fails() {
  local out n sum=0 found=0
  out="$(cat)"
  n="$(printf '%s' "$out" | grep -oE '[0-9]+ failed' | tail -1 | grep -oE '[0-9]+' || true)"
  if [[ -n "$n" ]]; then sum=$((sum + n)); found=1; fi
  n="$(printf '%s' "$out" | grep -oE 'Found [0-9]+ (error|diagnostic)' | tail -1 | grep -oE '[0-9]+' || true)"
  if [[ -n "$n" ]]; then sum=$((sum + n)); found=1; fi
  n="$(printf '%s' "$out" | grep -cE '^--- FAIL:' || true)"
  if [[ "${n:-0}" -gt 0 ]]; then sum=$((sum + n)); found=1; fi
  if [[ "$found" -eq 1 ]]; then printf '%s\n' "$sum"; else printf '\n'; fi
}

# 計測（FR-18）: skill 使用 / steer 発行を CSV に1行追記する。観測のみで、
# 失敗しても本処理を妨げない。置き場は plugin データ領域（evolve がここを読む）。
fw_log_usage() {
  # データ解決は evolve（skills/evolve/SKILL.md Step 1）と揃える: CLAUDE_PLUGIN_DATA →
  # plugin データ領域 → 最後の保険。CLI 経路（command の ! 行 / 素の flywheel）は
  # CLAUDE_PLUGIN_DATA 未設定なので、ここで plugin データ領域へ寄せないと evolve が読む
  # 本番 CSV と置き場が割れる（FR-31 の観測漏れの残り。経路で goal:start が別ファイルに散る）。
  local d csv
  d="${CLAUDE_PLUGIN_DATA:-$(ls -d "$HOME"/.claude/plugins/data/flywheel-* 2>/dev/null | head -1)}"
  d="${d:-$HOME/.claude/flywheel-data}"
  mkdir -p "$d" 2>/dev/null || return 0
  csv="$d/skill-usage.csv"
  [[ -f "$csv" ]] || echo "timestamp,skill" > "$csv" 2>/dev/null || return 0
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ),$1" >> "$csv" 2>/dev/null || true
}

# phase 述語（phase の意味論を1箇所に集約。各 hook は case 文を持たない）。
fw_gate_closed() { case "$1" in no-spec|designing) return 0 ;; *) return 1 ;; esac; }   # 実装ブロック中
fw_work_active() { case "$1" in spec-ready|implementing|polish|eval) return 0 ;; *) return 1 ;; esac; }  # loop が回すべき作業中 phase

# FR-32: eval が「薄い」（goal 固有の振る舞いを見ていない）か。eval_src=auto は
# プロジェクト全体の test/lint を自動検出しただけで、この goal の振る舞いは見ていない → 薄い。
# explicit（--eval）/ spec（design.md の完了条件）は人間が goal 固有に書いた eval なので薄くない。
# 用途: `flywheel go` の thick-eval 必須判定（FR-34 で verification ゲートは撤去・monitor に統合）。
fw_eval_is_thin() { [[ "$(fw_get '.eval_src')" == "auto" ]]; }
