#!/usr/bin/env bash
# error-fix command + debugger 教訓ゲートの不変条件を grep で assert する（FR-42 の grep-test 型）。
# 教訓ゲートの核: 不変性フィルタ / 2回ルール / doctrine soft-reference（タグ体系非複製）/
# 恒久層の無断書き込み禁止（HOTL）/ stateless / debugger の候補報告節。
source "$(dirname "${BASH_SOURCE[0]}")/grep-lib.sh"

CMD="$ROOT/commands/error-fix.md"
DBG="$ROOT/agents/debugger.md"

[ -f "$CMD" ] || fail "commands/error-fix.md が存在しない"

# C1: 教訓ゲートの4要素（不変性フィルタ / 2回ルール / doctrine 参照 / hook 発火テスト）
grep -q '不変性フィルタ' "$CMD" || fail "C1: 不変性フィルタが無い"
grep -q '2回ルール' "$CMD" || fail "C1: 2回ルールが無い"
grep -q 'doctrine\.md' "$CMD" || fail "C1: doctrine.md soft-reference が無い"
grep -q '発火テスト' "$CMD" || fail "C1: hook 昇格の発火テスト要件が無い"
ok "C1: 教訓ゲート4要素"

# C2: HOTL — memory は自動・恒久層（rule/hook）昇格は人間確認
grep -q '恒久層は無断で書かない' "$CMD" || fail "C2: 恒久層の無断書き込み禁止が無い"
grep -q 'AskUserQuestion' "$CMD" || fail "C2: 昇格の人間確認（AskUserQuestion）が無い"
ok "C2: HOTL（memory=自動 / 昇格=人間1問）"

# C3: stateless — flywheel 状態機械に乗らない宣言（C-2 整合）
grep -qE '状態機械.*乗りません' "$CMD" || fail "C3: stateless 宣言が無い"
ok "C3: stateless（状態機械に不接続）"

# C4: タグ体系を plugin に複製しない（SoT はユーザーの doctrine 側）
grep -q 'タグ体系を定義しない' "$CMD" || fail "C4: タグ体系の非複製宣言が無い"
ok "C4: doctrine SoT 非複製"

# C5: debugger agent の出力フォーマットに恒久教訓候補の報告節がある
grep -q '恒久教訓候補' "$DBG" || fail "C5: debugger に恒久教訓候補節が無い"
grep -q 'この agent は候補の報告まで' "$DBG" || fail "C5: debugger の書き込み禁止（報告まで）が無い"
ok "C5: debugger は候補報告のみ（書くのは main loop）"

echo "all ok"
