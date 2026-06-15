# FR-30 監視 council（done-gate 検証 council）— 要件

## 背景

flywheel の弱点を点検した結果、唯一のホールは「runnable な変更の挙動判定を**実装者本人**がやっている＝確証バイアス」だと特定した。eval（CLI exit code）は静的判定として既に客観的、loop-driver は eval 失敗の fail 数トレンドを既にカバーしている。だが「緑なのに要件から逸脱している」「緑なのに挙動が要件と違う」「緑のまま堂々巡りしている」は誰も見ていない。

記事「Loop Engineering」の罠1「検証の死角」と「Verifier を別に」がここに刺さる。そこで **done を宣言する直前に、実装文脈を持たない別エージェント群（観測者）に多観点で drift を検証させる** 設計ゲートを入れる。

## 機能要件

- **FR-30**: done-gate 検証 council。eval 緑（polish 後）→ done の直前に監視 council を1回走らせ、drift を検知したら done をブロックする。
  - overseer（`Skill: flywheel:monitor`）は done 境界で同期実行（実装は止まっているので main を占有してよい）。background / cron は使わない。
  - 観測者は独立コンテキスト・Read-only で **3 レンズ**（①要件逸脱 ②挙動 ③進捗/堂々巡り）。レンズはデータ化し後から増やせる。
  - 集約は overseer 単独（confidence-scoring + 降格マトリクス）。観測者間 peer cross-check はしない。
  - drift の執行は loop-driver に集約する。drift フラグは CLI（`flywheel monitor-set`）経由で state に書く（hook から Agent は spawn 不可・design-gate が `.flywheel/` への model 書込をブロックするため）。
  - **巻き戻し天井**: 自動で戻れるのは implementing まで。design / requirements レベルの drift は phase=designing に戻して**人間に hand-back**（HITL）。
  - **HITL**: `flywheel watch-focus "<text>"` で人間が監視の重点を指定でき、overseer が観測者に渡す。

## 非スコープ

- continuous mid-run watchdog（走行中ずっと監視する Shape B / v2）。drift→loop-driver の執行経路は共通なので無改修で後付け可能だが本要件では作らない。
- 観測者間の peer cross-check（相互 SendMessage 検証）。
- 3 レンズを超えるレンズ（security-drift / perf-drift 等）。データ化により後から追加可。
- implementing を超える自動巻き戻し（design/PRD は常に人間 hand-back）。
- monitor verdict の偽装対策（monitor は LLM 判断。決定論ゲートは eval が担う前提を維持）。
