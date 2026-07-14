# design.md の mid-flight 編集で .goal が古いまま残る件 — 撤回（no-op に戻す）

## 経緯（合意済み・掘り直し不要）

`plan/design.md` を implementing/eval/polish phase 中に Edit しても、`state.json` の
`.goal` フィールドが古いまま残り、`flywheel status` の `goal:` 行が最新の design.md と
食い違って見える（v0.8.46〜0.8.47 の goal 実行中に実際に踏んだ）。

この goal では2つの対策を試み、どちらも撤回した:

### 試案1: 見出し→.goal 自動同期（v0.8.48 初版）

`fw_work_active` のとき design.md の見出し行を `.goal` に自動書き込みする実装をした。
advisor レビューで revert: この分岐は「見出しが変わった」ときにしか発火せず、それは
goal の pivot そのもの——無害な共通ケースが無い。`.goal` は C-2 の frozen anchor で
monitor council の drift 検証 ground truth（`skills/monitor/SKILL.md`）。`eval_cmd`
（`set-eval` 経由の人間ゲートでしか動かない）との非対称を生みつつ無条件に自動追従させると、
表示は最新に見えるが検証の実体はより不整合になる。

### 試案2: 乖離検知時に警告のみ（.goal は不変）

自動書き換えを撤回し、乖離を検知したら additionalContext で警告するだけの実装に切り替えた。
しかし monitor council の drift-observer（挙動レンズ）が、この案も同じ根本欠陥を持つことを
実証した: **design.md の見出し（作業用タイトル）と `.goal`（adopt 時の正式文言）は、そもそも
一致する基準線が無い別種のテキスト**。今回のセッション中、pivot ではなく承認済み方針を
design.md に反映しただけの編集（見出しを分かりやすく付け替えた）で、実際に警告が誤発火した。
つまりこの分岐は「design.md を編集するたびに常時警告を出す」仕組みになり、本来検知すべき
本物の drift をノイズに埋没させる。試案1と同じ欠陥（一致しない前提のものを比較・追従させる）
が形を変えて再発しただけと判断した。

### 結論

**両案とも撤回。`hooks/design-validator.sh` は v0.8.48 以前の挙動（spec-ready 以降の
design.md 編集は無視）に戻す。** `.goal`（adopt 時の正式文言）が goal-of-record であり、
design.md の見出しが古い/違う文言に見えるのは cosmetic な問題であって実害は小さいと判断する。
本当に goal を pivot したい場合の明示的な人間確認フロー（`set-goal` 的な CLI 等）は、
必要になった時点で別 goal として起票する。

## 変更内容

- `hooks/design-validator.sh`: `fw_work_active` 分岐（見出し同期・警告のいずれも）を削除。
  spec-ready 以降の design.md への Edit/Write は no-op（既存の `fw_gate_closed` 分岐の
  みが残る）。
- `test/design-goal-sync.sh`: 削除（検証対象の機能が無くなったため）。

## 完了条件（eval）

```
bash test/run-all.sh
```

既存テストに regression が無いこと（新規テストは追加しない — 撤回なので検証対象が無い）。
