#!/usr/bin/env bash
# session-greeter が dormant 案内で /flywheel:guide を指すことを検証（FR-47）。
# greeter は SessionStart で Claude の context に injection される＝「使い方が分からず素手で大物を
# 作り始める」を入口で減らす導線。その導線の消失を CI で防ぐ grep ガード。
# grep-only なので副作用なしの grep-lib.sh を source（fail/ok/$ROOT）。
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/grep-lib.sh"

grep -q "/flywheel:guide" "$ROOT/hooks/session-greeter.sh" \
  || fail "session-greeter が /flywheel:guide への導線を出していない"

ok "greeter-guide: session-greeter が /flywheel:guide を案内（FR-47）"
