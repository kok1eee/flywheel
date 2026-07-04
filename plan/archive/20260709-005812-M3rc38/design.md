# design: adopt chain 着手前 checkpoint（Goal C・ROADMAP:54 follow-up）

## 背景・問題

- `hooks/loop-driver.sh` の adopt chain（FR-33・v0.8.14）は、done で backlog に次の goal があれば
  **無条件**に `flywheel next` を呼んで pop し、次 goal の設計へ連鎖する。start 経路は FR-35 で
  「連鎖前に go/no-go を1問 grill」という HOTL checkpoint が既にあるが、**adopt 経路には無い**。
- v0.8.24 観測（ROADMAP:54）: 対話セッション中に done→次 goal が無条件 auto-start すると、人間が
  別話題に移っていた場合に goal が宙に落ちる事故が実際に起きた（intent-router が本セッションで蒸発）。
- 2026-07-04 grill で対応方針を決定: **idle timeout 前提**を採用（対話検知は hook から対話性を
  判定する確実な信号が無く脆い／既定 `FLYWHEEL_NO_CHAIN` 化は adopt chain の「backlog を無人で
  一気に消化する」という価値を削る）。checkpoint は無条件で挟み、真に無人で回したい運用
  （`spawn-session` の flywheel 駆動等）は事前に `/config` の idle timeout をオプトインする側に倒す。
  2.1.200 で AskUserQuestion の自動継続（60s idle timeout）が廃止されたため、この委譲が唯一の
  無人運用パスになる（`skills/guide/SKILL.md` の Gotchas に既述）。

## 方針

### 1. peek してから next を呼ぶ（pop のタイミングを後ろにずらす）

現状 `loop-driver.sh`（done 分岐、`fw_chain_checkpoint` の直後）は `"$FW_CLI" next` を無条件で
呼んでから `fw_get '.entry'` で経路を判定している（next が backlog 先頭を pop 済み）。これだと
「いいえ」と答えても pop 済みで巻き戻せない。

`bin/flywheel next` は backlog 先頭行を `head -1 "$FW_BACKLOG"` で読んでから pop する（`bin/flywheel:147-148`）。
`entry` フィールドは backlog の jsonl 行自体に載っている（`add` 時点で書かれる。`bin/flywheel:126`）ので、
**pop せず先に peek できる**。loop-driver.sh は既に `hooks/lib/common.sh` を source しており
`$FW_BACKLOG` 変数（`common.sh:17`）に直接アクセスできる。

```bash
n="$(fw_backlog_count)"
if [[ "$n" -gt 0 && "${FLYWHEEL_NO_CHAIN:-}" != "1" ]]; then
  fw_chain_checkpoint   # 完了 goal の独立 change 確定は変更なし（FR-46）

  peek_entry="$(head -1 "$FW_BACKLOG" 2>/dev/null | jq -r '.entry // "start"' 2>/dev/null || echo start)"

  if [[ "$peek_entry" == "adopt" ]]; then
    peek_goal="$(head -1 "$FW_BACKLOG" 2>/dev/null | jq -r '.goal' 2>/dev/null || echo '?')"
    fw_log_usage "steer:chain-checkpoint"
    cat >&2 <<EOF
🔗 flywheel: done。backlog に次の adopt goal があります（残 $n 件・未起動）。
goal: $peek_goal
→ まず人間に AskUserQuestion で軽量チェックポイント:「次の goal に進みますか?」
  （合意済み設計の結晶化に進む前の一声。フル grill は不要）。
  ・はい      → '$FW_CLI next' を実行して起動 → 会話 / notes の合意を plan/design.md に結晶化
              （「## 完了条件（eval）」も）。合格で実装ゲートが開き、eval→done→次へ連鎖。
  ・いいえ/あとで → 何もしない。backlog はそのまま残ります（後で /flywheel:next で手動起動）。
⚠️ 無人運用（spawn-session の flywheel 駆動等）でこの質問により永久停止させたくない場合は、
   事前に /config で idle timeout をオプトインしてください
  （2.1.200 で AskUserQuestion の自動継続は廃止済み）。
EOF
    exit 2   # stop はブロック。実際の起動は人間の回答後、次ターンで model が next を呼ぶ
  fi

  # start 経路 / peek 失敗時（default "start"）は従来どおり即 next
  if "$FW_CLI" next >/dev/null 2>&1; then
    new_goal="$(fw_get '.goal')"
    # ここに来るのは entry=="start" のときのみ（adopt は上で return 済み）。
    # 既存の start-chain steer（go/no-go grill）は無変更。
    fw_log_usage "steer:start-chain"
    cat >&2 <<EOF
...(既存 v0.8.14 の start 分岐と同一・無変更)
EOF
    exit 2
  fi
  echo "⚠️ flywheel: 次 goal の自動起動に失敗しました。'$FW_CLI next' で手動起動してください（backlog 残 $n 件）。" >&2
  exit 0
fi
```

- **旧 `if entry == "adopt"`（next 呼び出し後・v0.8.14 の即時連鎖 steer）は削除**。adopt はもう
  peek 段階で return するため、next 呼び出し後の分岐に来るのは start のみ。
- start 経路・`FLYWHEEL_NO_CHAIN=1` 分岐は無変更（既存 4 ケースの回帰を test で担保）。

### 2. 曖昧点の解消（grill 確定事項）

「いいえ/あとで」の挙動は **新規 state を持たない**: backlog は pop されないまま残り、
`/flywheel:next` で後から手動起動できる。これは peek-before-pop の直接の帰結であり、
`FLYWHEEL_NO_CHAIN=1` の hard-stop 分岐（`echo ... 'flywheel next' で次へ。`）と同じ性質
（backlog 温存・手動再開）を adopt 経路にも一貫させる。

## Boundary（触る範囲）

- `hooks/loop-driver.sh`: done 分岐の adopt chain 部分（peek 追加・adopt 即時連鎖 steer を
  checkpoint steer に置き換え。start 分岐・NO_CHAIN 分岐は無変更）。
- `test/adopt-chain.sh`: 新規ケース追加
  - C5: entry=adopt で done → checkpoint steer が出る（exit 2・stderr に「AskUserQuestion」
    「次の goal に進みますか」等を含む）・**backlog が pop されていない**（行数不変）・
    state.phase は `done` のまま（次 goal に進んでいない）。
  - C6（回帰）: entry=start は既存どおり即 next → go/no-go grill steer・backlog は pop 済み。
  - C7（回帰）: `FLYWHEEL_NO_CHAIN=1` は従来どおり無条件 hard-stop・backlog 温存。
- README Changelog 追記 / `ROADMAP.md` の該当行（epic: 計画・分解の質、adopt chain auto 行の
  follow-up）を `✅ 実装済` に更新 / version bump（`plugin.json` / `marketplace.json` 2 箇所）。
- 非スコープ: 対話検知ロジックの実装（不採用・上記方針で決定済み）、`FLYWHEEL_NO_CHAIN` の
  既定値変更（不採用）、start 経路の go/no-go grill 自体の変更（無変更）。

## 後方互換・degrade

- `FLYWHEEL_NO_CHAIN=1` は既存どおり無条件 hard-stop（checkpoint 自体をバイパス。変更なし）。
- start 経路は無変更（peek が "start" を返す限り従来の即時 next + go/no-go grill）。
- peek に失敗（jq エラー・空行等）した場合は `"start"` にフォールバックし、従来の安全側
  （即 next して人間に go/no-go を聞く。何もせず止まるより安全）に倒す。
- hook 側は state を進めない（C-2 不変）。checkpoint への回答も `AskUserQuestion` という
  モデル側ツールで行われ、hook 自身は steer 文字列を出すだけ。

## 完了条件（eval）

```
bash test/run-all.sh
```

exit 0。満たすべき性質:

1. `test/adopt-chain.sh` C5: entry=adopt の done で checkpoint steer が出て exit 2、
   backlog 行数が pop 前後で不変、state.phase が `done` のまま。
2. `test/adopt-chain.sh` C6: entry=start は既存どおり即 next（回帰・backlog が 1 減る・
   go/no-go grill steer が出る）。
3. `test/adopt-chain.sh` C7: `FLYWHEEL_NO_CHAIN=1` は既存どおり無条件 hard-stop（回帰）。
4. 既存 test 全緑（`run-all` 集約）。

## 検証の落とし穴（前例由来）

- `head -1 "$FW_BACKLOG"` は pop しない（`sed`/`tail` で書き戻す既存 `next` 実装と混同しない）。
  peek は読み取り専用、書き込みは `next` 呼び出し時のみ発生させる。
- テストは chain-lib の `setup_done_ready` 等の precedent を使い、backlog.jsonl に `entry`
  フィールド込みの行を直接書いて（テスト harness の特権・C-2 対象外）検証する。
