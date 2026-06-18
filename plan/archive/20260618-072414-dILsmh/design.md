# design — FR-38: polish+monitor steer の融合

## 機構

`enter_polish`（loop-driver:56-63）は `fw_set_json polished true` → `fw_advance polish` →
`steer:simplify` 記録 → simplify steer → `exit 2`。この exit が monitor ゲート（112-137）の手前で
抜けるため polish と monitor が別停止になる。融合は **main eval-green 経路（line 110）の polish
呼び出し**を、simplify+monitor を1ターンで促す版に差し替える。

## 変更点

### 1. `hooks/loop-driver.sh` — `enter_polish` にモード引数を足して統合

新関数を増やさず既存 `enter_polish` を拡張（重複回避）。`$2="monitor"` で融合する:

```sh
enter_polish() {  # $1 = steer 冒頭文脈, $2 = "monitor" で融合
  fw_set_json polished true
  fw_advance polish "loop-driver: enter polish${2:+ +monitor}"
  fw_log_usage "steer:simplify"
  if [[ "${2:-}" == "monitor" ]]; then   # ${2:-} = set -u 下で 1 引数呼び出しでも落ちない
    fw_set_json monitor '{"status":"pending"}'
    fw_log_usage "steer:monitor"
    cat >&2 <<EOF
$1 done の前に2つを【同じターンで・この順に】:
1) Skill: simplify でコードを整理（polish: ...）。
2) 続けて Skill: flywheel:monitor で drift を検証（... 要件逸脱/挙動/進捗）。simplify の後に。
次の停止で eval 緑 + monitor verdict を一括判定 → clean なら done。
EOF
  else
    echo "$1 Skill: simplify でコードを整理してください（polish: ...）。次の停止で再度品質チェック。" >&2
  fi
  exit 2
}
```

### 2. eval-green 経路の呼び出しを NO_FUSE で分岐

```sh
if should_polish; then
  if [[ "${FLYWHEEL_NO_FUSE:-}" == "1" ]]; then
    enter_polish "✅ flywheel: eval 合格（$eval_cmd）。done の前に仕上げ:"      # 従来＝分離
  else
    enter_polish "✅ flywheel: eval 合格（$eval_cmd）。" monitor                 # 融合（既定）
  fi
fi
```

`should_polish` の副作用（skip 時に polished=true + メッセージ + return 1）は不変。skip なら従来
どおり monitor ゲートへ落ちる。**eval_cmd 未設定経路の `enter_polish`（1 引数）は変更しない**
（`${2:-}` で従来の simplify-only 枝に入る＝monitor 無関係）。monitor ゲート本体も不変。

## Tasks

- [ ] **T1** `enter_polish` に `$2="monitor"` モードを足して融合を統合（新関数は増やさない）+ eval-green 経路を NO_FUSE 分岐に。Boundary: loop-driver.sh の polish enter 周辺。Done: 融合時 monitor=pending prime + steer 両方。
- [ ] **T2** `test/polish-monitor-fuse.sh` 新規（下記4ケース）。Boundary: test/。Depends: T1。

## テスト（`test/polish-monitor-fuse.sh`）

chain-lib を source。`prime_polish`= setup_impl(eval green) 後に jq で polish=true/polished=false/
monitor=null/baseline_rev=""（baseline 空→fw_goal_diff_lines が空→should_polish が必ず polish 要と判定）。

- **C1（融合・既定）**: run_hook → exit 2・phase=polish・polished=true・**monitor.status=pending**。
  steer に simplify と monitor 両方を含む。
- **C2（エスケープハッチ）**: `FLYWHEEL_NO_FUSE=1` で run_hook → exit 2・polished=true・
  **monitor.status≠pending（prime しない）**。steer に simplify は有り monitor は無し。
- **C3（融合 entry→解決）**: prime→run_hook で融合発火（monitor=pending 確認）→ monitor=clean を
  記録 → run_hook → phase=done（融合の出力 state を起点に完全チェーンを通す）。
- **C4（degrade 安全）**: 融合発火後 monitor=pending のまま再 run_hook（model が monitor 飛ばし模擬）
  → exit 2・phase≠done（次停止の pending 分岐が拾い done すり抜けなし＝default-ON の安全根拠）。

## 完了条件（eval）

融合 ON で pending prime + 両 steer、NO_FUSE で従来挙動、融合後 clean→done。

```bash
bash test/polish-monitor-fuse.sh
```
