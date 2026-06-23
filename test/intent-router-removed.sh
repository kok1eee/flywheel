#!/usr/bin/env bash
# intent-router（legacy auto-engage hook）が完全撤去されたことを検証する（FR-45）。
# plan route が上位互換になり凍結済みの常駐 hook を削除。再混入を CI（run-all.sh）で防ぐ恒久ガード。
# grep ベース（runtime smoke 対象なし）なので副作用なしの grep-lib.sh を source（fail/ok/$ROOT）。
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/grep-lib.sh"   # fail/ok/$ROOT（副作用なし）

# hooks/ 消失時に grep が exit 2 を返し `!` で false-pass するのを防ぐガード（監視 council 指摘）。
[ -d "$ROOT/hooks" ] || fail "hooks/ ディレクトリが無い（参照ゼロ assert が false-pass し得る）"
[ ! -f "$ROOT/hooks/intent-router.sh" ] || fail "hooks/intent-router.sh がまだ存在する"
! grep -rqE "intent-router|FLYWHEEL_AUTO" "$ROOT/hooks/" || fail "hooks/ に intent-router|FLYWHEEL_AUTO の参照が残っている"

ok "intent-router-removed: hooks/ から intent-router/FLYWHEEL_AUTO を完全撤去"
