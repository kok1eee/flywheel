#!/usr/bin/env bash
# 改善B: flywheel backlog rm/mv（remove/reorder CLI）を検証する。
# live state / 本番 CSV を汚さないよう mktemp の使い捨て git リポを FW_ROOT にして実行する
# （fw_repo_root は cwd の git/jj root を返す → temp repo の .flywheel に backlog が作られる）。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
FW="$REPO/bin/flywheel"

fail() { echo "❌ FAIL: $1"; exit 1; }
ok()   { echo "✅ $1"; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export CLAUDE_PLUGIN_DATA="$TMP/data"; mkdir -p "$CLAUDE_PLUGIN_DATA"
REPO_T="$TMP/repo"; mkdir -p "$REPO_T"
( cd "$REPO_T" && git init -q && git config user.email t@example.com && git config user.name tester \
  && echo seed > seed.txt && git add -A && git commit -qm init ) || fail "git 初期化失敗"
cd "$REPO_T" || fail "cd 失敗"

BACKLOG="$REPO_T/.flywheel/backlog.jsonl"
# backlog を G1,G2,G3 の3件に整える
reset_backlog() {
  rm -f "$BACKLOG"
  "$FW" add "G1" --eval true >/dev/null 2>&1 || fail "add G1 失敗"
  "$FW" add "G2" --eval true >/dev/null 2>&1 || fail "add G2 失敗"
  "$FW" add "G3" --eval true >/dev/null 2>&1 || fail "add G3 失敗"
}
# backlog の goal 並びを "G1,G2,G3," 形式で返す
goals() { jq -r '.goal' "$BACKLOG" 2>/dev/null | tr '\n' ','; }

# C1: rm 2 → 2番目(G2)が消え順序保持
reset_backlog
"$FW" backlog rm 2 >/dev/null 2>&1 || fail "C1: backlog rm 2 が非ゼロ"
[ "$(goals)" = "G1,G3," ] || fail "C1: rm 2 後が G1,G3 でない: $(goals)"
ok "C1 rm 2 → G1,G3（順序保持）"

# C2: rm 範囲外/非整数 → exit1・backlog 不変
reset_backlog
"$FW" backlog rm 0 >/dev/null 2>&1 && fail "C2: rm 0 が成功してしまう"
"$FW" backlog rm 9 >/dev/null 2>&1 && fail "C2: rm 9 が成功してしまう"
"$FW" backlog rm x >/dev/null 2>&1 && fail "C2: rm x が成功してしまう"
[ "$(goals)" = "G1,G2,G3," ] || fail "C2: 範囲外 rm で backlog が変化: $(goals)"
ok "C2 rm 範囲外/非整数 → exit1・不変"

# C3: mv 1 3（前方→後方）→ G2,G3,G1
reset_backlog
"$FW" backlog mv 1 3 >/dev/null 2>&1 || fail "C3: mv 1 3 が非ゼロ"
[ "$(goals)" = "G2,G3,G1," ] || fail "C3: mv 1 3 後が G2,G3,G1 でない: $(goals)"
ok "C3 mv 1 3 → G2,G3,G1"

# C4: mv 3 1（後方→前方）→ G3,G1,G2
reset_backlog
"$FW" backlog mv 3 1 >/dev/null 2>&1 || fail "C4: mv 3 1 が非ゼロ"
[ "$(goals)" = "G3,G1,G2," ] || fail "C4: mv 3 1 後が G3,G1,G2 でない: $(goals)"
ok "C4 mv 3 1 → G3,G1,G2"

# C5: mv 同位置(no-op・exit0・不変) / mv 範囲外(exit1・不変)
reset_backlog
"$FW" backlog mv 2 2 >/dev/null 2>&1 || fail "C5: mv 2 2(no-op) が非ゼロ"
[ "$(goals)" = "G1,G2,G3," ] || fail "C5: mv 2 2 で順序が変化: $(goals)"
"$FW" backlog mv 1 9 >/dev/null 2>&1 && fail "C5: mv 1 9(範囲外) が成功してしまう"
[ "$(goals)" = "G1,G2,G3," ] || fail "C5: 範囲外 mv で順序が変化: $(goals)"
ok "C5 mv 同位置→no-op / 範囲外→exit1・不変"

# C6: 空 backlog で rm → exit1
rm -f "$BACKLOG"
"$FW" backlog rm 1 >/dev/null 2>&1 && fail "C6: 空 backlog の rm が成功してしまう"
ok "C6 空 backlog rm → exit1"

# C7: mv の n 側 reject（&& 第1オペランド）と空 backlog の mv（監視 council F002）
reset_backlog
"$FW" backlog mv 9 1 >/dev/null 2>&1 && fail "C7: mv 9 1(n範囲外) が成功してしまう"
"$FW" backlog mv x 1 >/dev/null 2>&1 && fail "C7: mv x 1(n非整数) が成功してしまう"
[ "$(goals)" = "G1,G2,G3," ] || fail "C7: n側 reject で順序が変化: $(goals)"
rm -f "$BACKLOG"
"$FW" backlog mv 1 2 >/dev/null 2>&1 && fail "C7: 空 backlog の mv が成功してしまう"
ok "C7 mv n側 reject / 空 mv → exit1"

# C8: rm 先頭/末尾（sed 境界）
reset_backlog
"$FW" backlog rm 1 >/dev/null 2>&1 || fail "C8: rm 1 が非ゼロ"
[ "$(goals)" = "G2,G3," ] || fail "C8: rm 1(先頭) 後が G2,G3 でない: $(goals)"
reset_backlog
"$FW" backlog rm 3 >/dev/null 2>&1 || fail "C8: rm 3 が非ゼロ"
[ "$(goals)" = "G1,G2," ] || fail "C8: rm 3(末尾) 後が G1,G2 でない: $(goals)"
ok "C8 rm 先頭/末尾 → 境界 OK"

# C9: 先頭ゼロは reject（(( )) の8進誤解釈回避・F001 回帰ガード）
reset_backlog
"$FW" backlog rm 08 >/dev/null 2>&1 && fail "C9: rm 08 が成功（8進誤解釈）"
"$FW" backlog mv 010 1 >/dev/null 2>&1 && fail "C9: mv 010 1 が成功（8進誤解釈）"
[ "$(goals)" = "G1,G2,G3," ] || fail "C9: 先頭ゼロ入力で順序が変化: $(goals)"
ok "C9 先頭ゼロ rm/mv → exit1・不変（8進バグ回帰）"

# C10: mv が .goal 以外（notes/eval_cmd）も原文保全
rm -f "$BACKLOG"
"$FW" add "GA" --eval "ty check" --notes "boundary: x.py" >/dev/null 2>&1 || fail "add GA 失敗"
"$FW" add "GB" --eval true >/dev/null 2>&1 || fail "add GB 失敗"
"$FW" backlog mv 1 2 >/dev/null 2>&1 || fail "C10: mv 1 2 が非ゼロ"
[ "$(goals)" = "GB,GA," ] || fail "C10: mv 1 2 後が GB,GA でない: $(goals)"
ga_notes="$(jq -r 'select(.goal=="GA") | .notes' "$BACKLOG")"
ga_eval="$(jq -r 'select(.goal=="GA") | .eval_cmd' "$BACKLOG")"
[ "$ga_notes" = "boundary: x.py" ] || fail "C10: mv で notes が失われた: '$ga_notes'"
[ "$ga_eval" = "ty check" ] || fail "C10: mv で eval_cmd が失われた: '$ga_eval'"
ok "C10 mv は notes/eval_cmd まで原文保全"

echo "✅ backlog-cli: 全10ケース緑（rm C1-C2,C8-C9 / mv C3-C5,C7,C9-C10 / 空 C6-C7）"
