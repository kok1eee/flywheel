# design: `flywheel set-eval` — 飛行中に eval_cmd を直す（gap B 解消）

## 背景・課題

gap B: `eval_cmd` は spec-ready 以降 immutable。design.md の「完了条件」から昇格した
eval_cmd が誤っていた / プロジェクト構成が変わった場合、飛行中（implementing/eval phase）に
直す手段が無く、`flywheel reset` で designing からやり直すしかない（前回の dogfood で「reset 地獄」を踏んだ）。

state を書き換える CLI 入口は既に `monitor-set`（FR-30）/ `verify-set`（FR-32）があり、
C-2 が禁じているのは「モデルが state.json を直接 Edit する」ことであって CLI 経由の書き込みではない。
よって `eval_cmd` / `eval_src` を CLI から書く専用サブコマンドを足せば、ゲートを壊さず飛行中に直せる。

## 何を作るか

`bin/flywheel` に **`set-eval <cmd>`** サブコマンドを追加する。`monitor-set` / `verify-set` と同型:

- 引数: `<cmd>`（必須・1個）。未指定なら usage を stderr に出して `exit 1`。
- ガード: `fw_state_exists`（state が無ければ「先に start」エラーで `exit 1`）。
- **phase 不問**: designing / implementing / eval どの phase でも書ける（飛行中に直すのが目的なので phase チェックは入れない）。
- `FLYWHEEL_HOOK` ガードは**付けない**: CLI は state を書ける（C-2 はモデル直編集のみ禁止。`monitor-set`/`verify-set` と同じ扱い）。
- 書き込み: `fw_set_str eval_cmd "$1"` と `fw_set_str eval_src "explicit"`（人間が明示指定した eval なので出所は explicit。これにより FR-32 の `fw_eval_is_thin`＝`eval_src==auto` も自然に外れる）。
- 確認出力: `echo "🔧 flywheel eval_cmd を更新: <cmd>（出所: explicit）"`。

### 追従させる箇所

1. `usage()` の Usage 一覧に `set-eval` の行を追加（`verify-set` の直後）。
2. `case "$cmd"` に `set-eval)` ブロックを追加（`verify-set)` の直後）。
3. `status` 表示は既に `eval_cmd:`（出所付き）を出しているので追加変更は不要（set-eval 後に出所が explicit に変わるのが見える）。

## 非スコープ

- backlog / 別 goal の eval は対象外（あくまで現在進行中の state を直す）。
- `--eval` フラグの再パースや polish 設定の変更は対象外（eval_cmd / eval_src のみ書く）。
- phase 遷移は行わない（`_advance` は使わない。あくまで state フィールドの上書き）。

## 完了条件（eval）

set-eval が「構文 OK・サブコマンドが存在し・実機で eval_cmd と eval_src=explicit を書ける」ことを
jj/git 外の mktemp -d 内で実証する（live state を壊さないため作業ディレクトリを temp に隔離）。

```
bash -n bin/flywheel && grep -q 'set-eval)' bin/flywheel && r="$(pwd)" && d="$(mktemp -d)" && cd "$d" && "$r/bin/flywheel" start evaltest >/dev/null && "$r/bin/flywheel" set-eval 'echo hi && true' >/dev/null && [ "$("$r/bin/flywheel" get .eval_cmd)" = 'echo hi && true' ] && [ "$("$r/bin/flywheel" get .eval_src)" = 'explicit' ] && cd "$r" && rm -rf "$d"
```
