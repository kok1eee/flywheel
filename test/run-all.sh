#!/usr/bin/env bash
# 共有テスト runner（FR-44）: test/ 配下の *.sh を実行し、1 本でも失敗したら非ゼロで集約する。
# ローカル実行と CI（.github/workflows/ci.yml）が同じ入口を通る。
# 除外: chain-lib.sh / grep-lib.sh は source 用ライブラリで単体実行しない。run-all.sh 自身も除外。
# 第1引数で対象ディレクトリを指定可（省略時は test/ 自身）。run-all-aggregation.sh が
# 「1本でも失敗→非ゼロ集約」を runtime 検証するために temp ディレクトリを渡して使う。
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIR="${1:-$SELF_DIR}"

fail=0
failed=()
for t in "$DIR"/*.sh; do
  base="$(basename "$t")"
  case "$base" in
    run-all.sh | chain-lib.sh | grep-lib.sh) continue ;;
  esac
  echo "=== $base ==="
  if bash "$t"; then
    :
  else
    fail=1
    failed+=("$base")
  fi
done

echo
if [[ "$fail" -ne 0 ]]; then
  echo "❌ FAILED (${#failed[@]}): ${failed[*]}"
  exit 1
fi
echo "✅ all tests passed"
exit 0
