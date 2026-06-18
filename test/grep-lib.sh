#!/usr/bin/env bash
# 副作用なしの共有ヘルパ（grep ベースの test 用）。source しても環境を変えない
# （chain-lib.sh と違い mktemp / git init / cd を一切しない）。提供: fail() / ok() / $ROOT。
fail() { echo "❌ $1"; exit 1; }
ok()   { echo "✅ $1"; }
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
