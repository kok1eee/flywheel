# design: monitor council のコスト比例制御（標的再council + lite council + diff_lines 計測）

## 背景・問題

monitor-verdicts.csv の実測（2026-07-09 時点 34 行・約14goal分）: council は 1 goal あたり平均
約2.4回実行されている。観測者は v0.8.40 で Sonnet 固定済み（トークン単価は下がった）が、**回数**
自体を減らす余地が手つかずだった。2つの構造的な無駄:

1. **drift 修正後の再検証が毎回フル3体**。drift(impl) は「指摘された1レンズの問題」であることが
   多いのに、修正後は要件逸脱/挙動/進捗の3レンズを丸ごと再実行している。
2. **小さい goal でも初回からフル3体**。docs 修正・frontmatter 変更のような小さい diff の goal
   （直近実績で212〜330行）でも、大きい実装 goal と同じ重さで council が走る。

いずれも「council を丸ごと skip する」のではない（2026-07-09 会話で明示的に非採用——self-graded
skip の穴を再開けるため）。**回す体数とレンズ数を diff の実態に応じて絞る**のが今回のスコープ。

## 方針

### 1. lite council（初回 council の軽量化）

`hooks/loop-driver.sh` の monitor pending 初回分岐（`mstatus` が空の分岐・現状139-151行）で、
`fw_goal_diff_lines` を計算し閾値と比較。`watch_focus` 設定時は常にフル（安全弁①）。

```bash
diff_n="$(fw_goal_diff_lines)"
wf="$(fw_get '.watch_focus')"
lite_th="${FLYWHEEL_MONITOR_LITE_DIFF:-250}"
if [[ -n "$wf" ]]; then
  hint=""   # フル（watch_focus 優先・安全弁①）
elif [[ -n "$diff_n" && "$diff_n" -lt "$lite_th" ]]; then
  hint=" diff は ${diff_n} 行（閾値 ${lite_th} 未満・FLYWHEEL_MONITOR_LITE_DIFF）。lite council 可: 観測者1体に3レンズ（要件逸脱/挙動/進捗）を統合して fan-out してよい。"
else
  hint=""   # フル（diff 大 or 計測不能）
fi
echo "🔎 flywheel: eval 合格...done の前に Skill: flywheel:monitor で drift を検証してください（観測者を fan-out: 要件逸脱 / 挙動 / 進捗）。${wf:+ 重点(watch-focus): $wf}${hint}" >&2
```

`diff_n` 空（baseline なし・計測不能）は `should_polish` と同じ安全側＝フル council。

### 2. last_drift の記録と標的再council

`hooks/loop-driver.sh` の drift(impl) 実行分岐（現状161-198行、`mstatus == "drift"`）で、
`fw_set_json monitor null`（クリア）の**前**に lens/level/diff_lines を退避する:

```bash
elif [[ "$mstatus" == "drift" ]]; then
  mlevel="$(fw_get '.monitor.level')"
  mreason="$(fw_get '.monitor.reason')"
  mlens="$(fw_get '.monitor.lens')"          # 新規（下記1参照）
  cur_diff="$(fw_goal_diff_lines)"
  fw_set_json last_drift "$(jq -cn --arg l "$mlens" --arg lv "$mlevel" --arg d "$cur_diff" \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{lens:$l, level:$lv, diff_lines:$d, ts:$ts}')"
  fw_set_json monitor null
  ...(既存の case $mlevel 分岐は不変)
```

初回 pending 分岐（上記1）の先頭で `last_drift` を消費・one-shot クリアする形に拡張:

```bash
ld_level="$(fw_get '.last_drift.level')"
if [[ -n "$wf" ]]; then
  hint=""                                                          # 安全弁①
elif [[ -n "$ld_level" ]]; then
  if [[ "$ld_level" == "design" || "$ld_level" == "requirements" ]]; then
    hint=""                                                        # 安全弁②: 設計やり直し後はフル
  else
    ld_diff="$(fw_get '.last_drift.diff_lines')"
    delta=$(( ${diff_n:-0} - ${ld_diff:-0} ))
    if [[ -z "$diff_n" || -z "$ld_diff" || "$delta" -gt "$lite_th" ]]; then
      hint=""                                                      # 安全弁③: 修正 diff が大きい/計測不能
    else
      ld_lens="$(fw_get '.last_drift.lens')"
      hint=" 直前の drift 修正の再検証です。標的再council 可: 指摘レンズ（${ld_lens:-不明}）のみ観測者1体で再検証してよい（他レンズは前回 clean 相当）。"
    fi
  fi
  fw_set_json last_drift null                                      # one-shot 消費
elif [[ -n "$diff_n" && "$diff_n" -lt "$lite_th" ]]; then
  hint=" ...lite council 可..."                                     # 上記1
else
  hint=""
fi
```

- 安全弁①〜③は grill で確定した「標準セット」。`delta` の閾値は `FLYWHEEL_MONITOR_LITE_DIFF` を
  再利用（新しい env は増やさない）。
- design/requirements level drift は `fw_advance designing` で phase が戻り、その後
  設計→spec-ready→実装→eval→polish を経て再度 pending に達する。`last_drift` はその間 state に
  残るが、次に消費されるのはその新しいサイクルの初回 pending 到達時であり意図どおり（安全弁②が発火）。

### 3. `.monitor.lens` を state に保存（1の前提）

`bin/flywheel` の `monitor-set` ケースで、`--lens` の正規化（引用符/改行除去・カンマ→パイプ）を
**CLI 側で1回だけ**行い、state.monitor と CSV の両方に同じ正規化済み値を渡す（現状は
`fw_log_monitor_verdict` 内だけで正規化しており state には保存されていない）:

```bash
_lens_norm="$(printf '%s' "$_lens" | tr -d '"\n' | tr ',' '|')"
...
fw_set_json monitor "$(jq -cn --arg s "$_ms" --arg l "$_ml" --arg r "$_mr" --arg fp "$_mfp" \
  --arg lens "$_lens_norm" --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '{status:$s, level:$l, reason:$r, fingerprint:$fp, lens:$lens, ts:$ts}')"
if [[ "$_ms" != "pending" ]]; then
  ...(既存の warning 2行は不変)
  fw_log_monitor_verdict "$_ms" "$_ml" "$_lens_norm" "$(fw_goal_diff_lines)"
fi
```

`fw_log_monitor_verdict`（`hooks/lib/common.sh`）は**正規化済み文字列を受け取る側に契約変更**
（内部の `tr` 呼び出しを削除・引数はそのまま CSV へ）。呼び出し元がここ1箇所のみなので影響範囲は
閉じている。

### 4. monitor-verdicts.csv に diff_lines + mode 列（6列化・polish で追加）

`fw_log_monitor_verdict` を6列ヘッダ + 6列データに拡張（当初案の5列＝diff_lines のみから、
simplify altitude 指摘で `mode`（lite/targeted/full・実際に回した council の重さ）も追加。
これが無いと「lite/full の捕捉率を比較する」という本 goal の目的自体が達成できないため）。
**既存 CSV（4列・v0.8.33〜v0.8.41 / 開発中の5列）の移行**: `_fw_log_csv` はファイル存在時に
ヘッダを書き直さない仕様のため、`fw_log_monitor_verdict` 内で一度だけ明示的にヘッダ行を
新形式へ置換する（データ行は不変・旧行は末尾列が欠けたまま＝空とみなして読める）:

```bash
fw_log_monitor_verdict() {
  local d csv hdr; d="$(fw_data_dir)"; csv="$d/monitor-verdicts.csv"
  if [[ -f "$csv" ]]; then
    hdr="$(head -1 "$csv" 2>/dev/null)"
    if [[ "$hdr" == "timestamp,verdict,level,lenses" || "$hdr" == "timestamp,verdict,level,lenses,diff_lines" ]]; then
      sed -i '1s/.*/timestamp,verdict,level,lenses,diff_lines,mode/' "$csv" 2>/dev/null || true
    fi
  fi
  _fw_log_csv monitor-verdicts.csv "timestamp,verdict,level,lenses,diff_lines,mode" "$1,${2:-},${3:-},${4:-},${5:-}"
}
```

呼び出しは `fw_log_monitor_verdict "$_ms" "$_ml" "$_lens_norm" "$_diff" "$_mode"`（上記3）。
`monitor-set` に `--mode <lite|targeted|full>`（任意・省略時 `full`）を追加し、`--lens` と同型で
先抜きする。state.monitor にも `mode`/`diff_lines` を保存し、`diff_lines` は
`hooks/loop-driver.sh` の drift(impl) 分岐が `.monitor.diff_lines` を読み回すことで
`fw_goal_diff_lines` のプロセスを跨いだ二重計算を避ける（simplify efficiency 指摘）。

### 5.5 修正: FR-38 融合パスで lite hint が到達不能だったバグ（monitor drift(design) 対応）

polish 段の monitor council で drift(design) を検出（2026-07-09）。**既定設定（`FLYWHEEL_NO_FUSE`
未設定＝FR-38 融合 ON）では、diff 30〜250行の通常サイズ goal で lite hint が一度も出ない**構造的
欠陥だった。

原因: `hooks/loop-driver.sh` は eval 初回緑・`should_polish` が true のとき
`enter_polish "..." monitor` を呼び、**その場で** `monitor='{"status":"pending"}'` をセットして
`exit 2` する（FR-38 融合）。これは上記1で追加した `mstatus` が空の分岐（`monitor_hint()` 呼び出し）
**より前**に発火するため、その分岐に到達する前にプロセスが終わり lite hint が計算されない。
lite hint が出るのは diff<30（polish 自体が自己 skip）か `FLYWHEEL_NO_FUSE=1`（非既定）のときだけ
——どちらも実運用の通常フローではない。標的再council は無事（`should_polish` は goal につき1回
しか true を返さないため、2回目以降の停止は必ず `mstatus` 分岐を正規に通る）。

`test/monitor-cost-control.sh` はこのバグを検出できない構造だった: 全ケースが `setup_impl`
（`.polish=false | .polished=true` を強制）を使っており、FR-38 融合パス自体を経由しないため。

**修正**: `enter_polish` の融合分岐（`$2=="monitor"`）内でも `monitor_hint()` を呼び、結果を
combined steer に含める。`diff_n`（top-level で計算済み・関数からグローバル参照可能）と
`watch_focus`（融合分岐内で新規に取得）を渡す:

```bash
enter_polish() {  # $1 = steer 冒頭文脈, $2 = "monitor" で融合
  fw_set_json polished true
  fw_advance polish "loop-driver: enter polish${2:+ +monitor}"
  fw_log_usage "steer:simplify"
  if [[ "${2:-}" == "monitor" ]]; then
    fw_set_json monitor '{"status":"pending"}'
    fw_log_usage "steer:monitor"
    local wf hint lite_th
    wf="$(fw_get '.watch_focus')"
    lite_th="${FLYWHEEL_MONITOR_LITE_DIFF:-250}"
    hint="$(monitor_hint "$wf" "$diff_n" "$lite_th")"
    cat >&2 <<EOF
$1 done の前に2つを【同じターンで・この順に】:
1) Skill: simplify でコードを整理（polish: reuse/簡素化/効率/altitude）。
2) 続けて Skill: flywheel:monitor で drift を検証（観測者 fan-out: 要件逸脱/挙動/進捗）。simplify の結果を検証するので必ず simplify の後。${wf:+ 重点(watch-focus): $wf}${hint}
次の停止で eval 緑 + monitor verdict を一括判定 → clean なら done。
EOF
  else
    echo "$1 Skill: simplify でコードを整理してください（polish: reuse/簡素化/効率/altitude）。次の停止で再度品質チェックし、通れば done です。" >&2
  fi
  exit 2
}
```

`monitor_hint` は関数定義順としては `enter_polish` より後だが、両方とも実際に**呼ばれる**のは
スクリプルート部の後段（`if rc -eq 0` 以降）なので、bash の「呼び出し時に定義済みなら可」の
規約上は問題ない（定義の textual 順序は無関係）。`diff_n` は top-level 変数（関数内 `local` で
シャドウされていない）なので `enter_polish` から素で参照できる。

`last_drift` はこの融合分岐が発火する時点（goal の最初の eval 緑）では必ず未設定（drift(impl) は
1回も起きていない）なので `monitor_hint` は素直に lite 判定のみ行う（既存 last_drift 消費ロジックと
競合しない）。

新規テストケース: `setup_done_ready` 相当ではなく実際に FR-38 融合パス（`polish=true`・
`polished=false`）を通す fixture を用意し、diff 30〜250行の範囲で `enter_polish` 経由の steer に
lite hint が出ることを検証する。

### 5. skills/monitor/SKILL.md — lite/標的モードの解釈手順 + `--mode` 記録 + Gotcha

Step 2 冒頭に追記: loop-driver の steer に「lite council 可」「標的再council 可」の一文がある
ときだけ、それぞれ以下の縮小 fan-out を選んでよい。**steer に明示が無い限り自己判断で縮小しない**
（self-graded 化防止）:

- **lite**: 3レンズを統合した1つの charter で `flywheel:drift-observer` を1体だけ spawn
  （「以下の3観点を1レンズとして見てください: 要件逸脱／挙動／進捗」）。
- **標的**: steer が示した lens 1つだけの charter で観測者を1体 spawn（他レンズは前回 clean 相当
  として overseer 側で明記し verdict に残す）。

Step 4（verdict 記録）に追記: lite/標的を選んだときは `flywheel monitor-set ... --mode lite`
/ `--mode targeted` を必ず添える（捕捉率比較のデータ源。通常のフル3レンズは省略可＝ `full` 既定）。

AUTO-GOTCHAS 節に1項追記: 「lite/標的 council は loop-driver の steer が明示したときだけ選ぶ。
diff が小さそうに見える・時間が無い等の自己判断で観測者を減らさない（self-graded 化の再発防止）」。

## Boundary（触る範囲）

- `bin/flywheel`: `monitor-set` ケース（lens 正規化を CLI 側に移動・`--mode` 追加・
  state.monitor に `lens`/`mode`/`diff_lines` 追加・`fw_log_monitor_verdict` 呼び出しに
  diff_lines/mode 引数追加）。
- `hooks/lib/common.sh`: `fw_log_monitor_verdict`（契約変更: 正規化済み lens を受け取る・
  diff_lines/mode 引数追加・CSV 6列ヘッダ移行）。
- `hooks/loop-driver.sh`: `should_polish`（引数で diff 事前計算値を受け取れるよう変更）+
  新規 `monitor_hint()` 関数（`should_polish`/`monitor_bump` と対称な named function に
  hint 分岐を抽出。last_drift の one-shot クリアを分岐に関わらず1箇所に統一）+ monitor
  pending 初回分岐（`fw_goal_diff_lines` をこのターン1回だけ計算し should_polish と共有）+
  drift(impl) 分岐（last_drift 退避・diff_lines は `.monitor.diff_lines` を読み回す）。
- `skills/monitor/SKILL.md`: Step 2 冒頭に lite/標的の解釈手順 + Step 4 に `--mode` 記録指示 +
  AUTO-GOTCHAS 1項。
- `test/monitor-lens-csv.sh`: 6列対応（C1/C1b のヘッダ・行 assert を更新）+ 旧4列/5列ヘッダからの
  移行を検証する新ケース（C0/C0b）+ `--mode` 記録の新ケース（C10）。
- `test/monitor-cost-control.sh` 新規（loop-driver の steer 出し分けを検証。chain-lib の
  `jq_patch`/`seq` 既存イディオムを使用）。
- 出荷規約: README Changelog / ROADMAP 該当行 / version bump **v0.8.42**（plugin.json /
  marketplace.json 2箇所）。
- 非スコープ: council を丸ごと skip する閾値（2026-07-09 会話で明示的に非採用）、simplify/polish
  側への比例制御の拡張（別途 grill 済み・現状維持と決定）、既存 monitor-verdicts.csv 旧行への
  diff_lines/mode 遡及補完（不可能・空のまま）、steer が提示した mode と実際に記録された mode の
  不一致を機械警告する仕組み（simplify altitude 指摘で候補に挙がったが、loop-driver の hint 判定
  ロジックを bin/flywheel 側に複製する必要がありスコープ超過・improvements.md へ退避）。

## 後方互換・degrade

- `hint` が空文字（フル council）のケースでは steer 文言が従来と完全に同一（既存 test の回帰なし）。
- `--lens` を使わない古い呼び出し（`_lens` 空）は `_lens_norm` も空になり、`state.monitor.lens` は
  空文字＝従来どおり「レンズ不明」として扱われる。
- `fw_log_monitor_verdict` の契約変更（正規化済み文字列を受け取る）は呼び出し元が `bin/flywheel`
  の1箇所のみなので、他の壊れは無い（grep で呼び出し元を確認する）。
- lite/標的 council は **skill 側の任意選択**（steer は「可」であって「必須」ではない）。モデルが
  無視してフル3体を回しても壊れない＝安全側 degrade。
- last_drift の one-shot クリアはコード内で明示（消費と同時に null 化）。読み忘れて残留しても
  次回の hint 判定に一度だけ影響するだけで、state 自体を壊さない。

## 完了条件（eval）

```
bash test/run-all.sh
```

exit 0。満たすべき性質:

1. `test/monitor-lens-csv.sh`: 6列ヘッダ・6列データで CSV 記録（既存 C1-C9 を6列前提に更新）+
   旧4列/5列ヘッダファイルが新規行の記録時に6列ヘッダへ移行される新ケース（C0/C0b）+ `--mode`
   が state と CSV に記録される新ケース（C10）。
2. `test/monitor-cost-control.sh`（新規）:
   - diff < 閾値・watch_focus 空・last_drift 空 → steer に「lite council 可」を含む。
   - diff ≥ 閾値 → steer に lite/標的 の文言を含まない（フル）。
   - watch_focus 設定時は diff が閾値未満でも lite 文言を含まない（安全弁①）。
   - drift(impl) 実行後、次の pending 到達時に diff 増分が閾値未満 → steer に「標的再council 可」
     + 指摘 lens を含む。
   - drift(impl) 後、diff 増分が閾値以上 → 標的 hint を含まない（安全弁③）。
   - drift(design) 後の次 pending 到達時は lite/標的いずれの hint も含まない（安全弁②）。
   - watch_focus + last_drift 併存時も last_drift は one-shot クリアされる（stale化バグの回帰）。
   - drift(impl) 実行時に last_drift（lens/level/diff_lines）が実際に退避される（ラウンドトリップ）。
3. `state.monitor.lens`/`state.monitor.mode` が `monitor-set drift ... --lens a,b --mode targeted`
   後にそれぞれ `a|b`/`targeted` で保存されている。
4. 既存 test 全緑（run-all 集約・特に polish-monitor-fuse / monitor-fingerprint の回帰）。

## 検証の落とし穴（前例由来）

- `fw_goal_diff_lines` は baseline 無しで空文字を返す（`0` ではない）。bash 算術 `$(( diff_n - ld_diff ))`
  に空文字を渡すと構文エラーになるため、比較前に `-z` ガードを必ず通す（`should_polish` の
  既存パターンを踏襲）。
- `last_drift` の one-shot クリアを **hint 判定の分岐すべて**（安全弁②③・lite 提示の3パターン）で
  確実に通すこと。片方の分岐にだけ `fw_set_json last_drift null` を書いて漏らすと、次回以降ずっと
  古い last_drift を読み続ける stale 化バグになる（FR-50 の stale clean と同種の穴）。
- `sed -i` によるヘッダ移行は `_fw_log_csv` 呼び出しの**前**に実行する（後だと新形式ヘッダの直後に
  旧データ行という順序は変わらないが、念のため書き込み順を明示してテストする）。
- `fw_log_monitor_verdict` の契約変更後、`grep -rn "fw_log_monitor_verdict"` で呼び出し元が
  `bin/flywheel` の1箇所のみであることを実装前に確認する（他に隠れた呼び出し元があれば二重正規化
  or 正規化漏れが起きる）。
