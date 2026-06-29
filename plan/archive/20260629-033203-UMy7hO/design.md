# design — backlog remove/reorder CLI（改善B）

## 背景

adopt chain（FR-33）が主経路化（最近 goal 起動の adopt 18 > start 17）したが、backlog は
`flywheel add`（末尾追加）と `next`（先頭 pop）しか操作できず、**特定項目の削除・並べ替えができない**。
`.flywheel/` は C-2 でモデル編集禁止＝手編集も不可。誤積み・重複・優先変更を直す術が無い
（ROADMAP dev infra epic）。**CLI に backlog の rm/mv を足す**（CLI の state 書き込みは C-2 対象外）。

## 何を作るか（ファイル/関数レベル）

### 1. `bin/flywheel` に `backlog` subcommand を追加（`case "$cmd"` の `reset)` 前後に新 case）

```
flywheel backlog rm <n>          # n 番目（1-indexed・flywheel list の番号）を削除
flywheel backlog mv <n> <pos>    # n 番目を pos 位置へ移動（並べ替え）
flywheel backlog                 # サブコマンド無し → usage（閲覧は flywheel list）
```

- **共通**: `[[ -s "$FW_BACKLOG" ]]` で空 backlog を弾く。`n`/`pos` は整数＆`1..total`（`fw_backlog_count`）範囲チェック。範囲外・非整数は usage を `>&2` に出して `exit 1`。
- **rm**: 削除前に `sed -n "${n}p"` で goal を読み報告 → `sed "${n}d"` で行削除（sed は行番号操作＝JSON 内容に非依存）。`🗑️ backlog #n を削除（残 M 件）: <goal>`。
- **mv**: `n==pos` は no-op で `exit 0`。それ以外は **awk で原ファイルを配列読み**し、n を抜いて pos 位置へ挿入して書き戻す（JSON 行は awk の `-v` を経由させず原文のまま保持）:
  ```awk
  { lines[NR]=$0 }
  END { total=NR; moved=lines[n]; c=0
        for(i=1;i<=total;i++) if(i!=n) rest[++c]=lines[i]
        r=0; for(p=1;p<=total;p++){ if(p==pos) print moved; else print rest[++r] } }
  ```
  `↕️ backlog #n → #pos へ移動: <goal>`。書き戻しは `> "$FW_BACKLOG.tmp" && mv`（next と同方式）。
- **phase ガードは不要**: backlog は「未来の goal キュー」で進行中 goal の `state.json` に触れない（`next` の進行中ガードとは別物）。

### 2. `test/backlog-cli.sh`（run-all が自動 glob）

mktemp の使い捨て領域（`CLAUDE_PLUGIN_DATA` 分離は不要だが live `.flywheel` を汚さないよう temp repo を FW_ROOT に）。`flywheel add` で 3 件積んでから:

- **C1 rm**: `backlog rm 2` → 残 2 件・2 番目の goal が消え 1/3 番目が残る・順序保持。
- **C2 rm 範囲外**: `rm 0` / `rm 9` / `rm x` → `exit 1`・backlog 不変。
- **C3 mv（前方→後方）**: 3 件で `mv 1 3` → 順序が [2,3,1] になる。
- **C4 mv（後方→前方）**: `mv 3 1` → [3,1,2]。
- **C5 mv 同位置/範囲外**: `mv 2 2`（no-op・exit0・不変）/ `mv 1 9`（exit1・不変）。
- **C6 空 backlog**: `rm 1` → `exit 1`・「空です」。

各ケースは `flywheel list` の出力 or backlog.jsonl の goal 並びで検証（goal 文字列で照合）。

## 非スコープ

- `clear`（全削除）・対話選択・複数指定（範囲 `rm 2-4`）は今回入れない（rm/mv の最小スコープ）。
- backlog 編集の undo は持たない（jj op log は repo 側のみ・`.flywheel` は gitignore）。

## 完了条件（eval）

```
bash test/run-all.sh
```

`test/backlog-cli.sh`（C1–C6）が自動登録され、既存全スイートと共に緑であること。
