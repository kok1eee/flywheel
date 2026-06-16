# FR-32: verification を「eval が薄いプロジェクト」限定の done 前 blocking ゲート化

## 背景・動機

skill-usage.csv（FR-18 計測）で `steer:verification` が 8 回発行されたのに
`flywheel:verification` の実行は 0 件だった。原因調査の結論は **バグではなく設計どおり**:

- `simplify`(loop-driver.sh) / `monitor` は `exit 2` の **blocking** ゲート
  （停止を拒否して skill 実行を強制）なので必ず撃たれる。
- `verification` は **done 到達後の optional nudge**（`exit 0`）。強制力ゼロなので
  撃たれないのが正常。同じ "steer 従命率" の分母に並べていたのが誤解の元だった。

さらに flywheel 自身の `eval_cmd` は「実際に flywheel を mktemp で動かす」振る舞いテストを
内包しており、挙動エビデンスは eval に含まれる。よって verification の **常時** blocking 化は過剰。
**eval が薄い（goal 固有の振る舞いを見ていない）プロジェクトに限って** blocking にするのが妥当。

## 方針（grill で確定）

1. **条件**: `eval_src == auto` のときだけ verification を blocking にする。
   - `auto` = プロジェクト全体の test/lint を自動検出しただけ。goal 固有の振る舞いは見ない＝薄い。
   - `explicit`（`--eval`）/ `spec`（design.md の完了条件から昇格）= 人間が goal 固有に書いた
     eval。本人が done 判定可能と宣言済みなので強制対象外（不信任＝過剰を避ける）。
   - `eval_cmd` 空（`eval_src` 空）は loop-driver の no-eval 分岐で stop 許可され、gate に到達しない。
   - 判定は既存の `state.eval_src` に乗る。**コマンド文字列の解析はしない**。
2. **判定機構**: monitor の `monitor-set` 機構をミラーする（FR-30 と同型）。
3. **ゲート位置**: monitor ゲートの後・done の直前（旧 nudge と同じ位置）。
4. **計測**: 旧 optional nudge は撤去し、`fw_log_usage "steer:verification"` を
   blocking ゲート側へ移す。これで `steer:verification` 従命率が初めて意味を持つ。

## 変更点（ファイル・関数レベル）

### hooks/lib/common.sh
- `fw_eval_is_thin()` を追加: `[[ "$(fw_get '.eval_src')" == "auto" ]]`
  （薄さ判定を1箇所に集約。loop-driver は case 文を持たない＝既存の述語集約方針に合わせる）

### bin/flywheel
- `verify-set <clean|pending> [evidence]` サブコマンド追加（`monitor-set` をミラー）。
  `state.verification = {status, evidence, ts}` を書く。`clean` を正とし、未知値は弾く
  （loop-driver 側も clean 以外は通さない＝fail-closed）。usage にも1行追加。

### hooks/loop-driver.sh
- `monitor clean` → done へ進む経路（`fw_advance done` の **前**）に verification ゲートを挿入:
  - `if fw_eval_is_thin && [[ verification.status != clean ]]:` → steer 出力 +
    `fw_log_usage "steer:verification"` + `exit 2`
  - cap: `verification_attempts`（`monitor_bump` と同じ bump パターン、`vcap`）。cap 到達で
    人間に返す（薄い eval で永遠に done できない事故を防ぐ）。
  - done 直前で `verification` / `verification_attempts` をクリア。
  - eval が緑から崩れたら同カウンタを破棄（monitor と同様、緑領域専用カウンタ）。
- 旧 optional nudge（`挙動エビデンスも残すなら…` + 旧 `fw_log_usage "steer:verification"`）を撤去。

### 既知の限界（設計を止めない）
- `verify-set` の evidence は LLM 自己申告で機械検証不能（monitor の clean/drift と同じ本質的限界）。
- flywheel 自身は `eval_src=spec` なので **このゲートは発火しない**＝ドッグフードで踏めない。
  検証は mktemp 上の auto 検出プロジェクトで行う。

## 完了条件（eval）

```
bash -n bin/flywheel && bash -n hooks/loop-driver.sh && bash -n hooks/lib/common.sh && ./bin/validate-plan design && grep -q 'verify-set' bin/flywheel && grep -q 'fw_eval_is_thin' hooks/lib/common.sh && grep -q 'verification' hooks/loop-driver.sh && FW="$PWD/bin/flywheel"; LIB="$PWD/hooks/lib/common.sh"; T="$(mktemp -d)"; ( cd "$T" && printf '{"scripts":{"test":"true"}}' > package.json && "$FW" start "auto-probe" >/dev/null 2>&1 && "$FW" get '.eval_src' | grep -qx auto && ( source "$LIB"; fw_eval_is_thin ) && "$FW" verify-set clean >/dev/null && "$FW" get '.verification.status' | grep -qx clean ) && T2="$(mktemp -d)"; ( cd "$T2" && "$FW" start "thick" --eval "true" >/dev/null 2>&1 && "$FW" get '.eval_src' | grep -qx explicit && ! ( source "$LIB"; fw_eval_is_thin ) )
```
