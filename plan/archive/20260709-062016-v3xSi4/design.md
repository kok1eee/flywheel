# design: flywheel note（進行中文脈の軽量スナップショット）

## 背景・問題

ROADMAP「進行中文脈の軽量スナップショット」（出所: 2026-06-16 pachitown-kb OKF 作業）:
`flywheel status` と `.claude/journal.md`（セッション間 handoff）の中間が無い。compact や
セッション中断で「今手に持っている作業仮説・なぜ今これをやっているか」が揮発する一方、
journal を書くほどでもない mid-session の区切りは記録先が無い。

2026-07-09 Fable 5 grill で確定: 作る（最小形）。書ける期間は **goal 進行中限定**
（`fw_state_exists` ガード・`set-eval`/`watch-focus` と同型）。greeter 同梱は **最新3件**
（context 税と復元力のバランス）。

## 方針

### 1. `flywheel note "<text>"`（bin/flywheel 新規サブコマンド）

`set-eval`/`watch-focus` と同型: `fw_state_exists` ガード（無ければ拒否）・phase 不問。
`FLYWHEEL_HOOK` ガード無し（CLI からの書き込みは C-2 対象外＝モデル直編集のみ禁止）。

```bash
note)
  [[ $# -lt 1 ]] && { echo "flywheel note \"<text>\"" >&2; exit 1; }
  fw_state_exists || { echo "flywheel note: state がありません（goal 進行中のみ・先に start/adopt）" >&2; exit 1; }
  mkdir -p "$FW_DIR"
  printf -- '- [%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" >> "$FW_DIR/notes.md"
  echo "📝 flywheel note を記録しました。"
  ;;
```

置き場は `$FW_DIR/notes.md`（`.flywheel/notes.md`）。`.flywheel/` は既に gitignore 済み
（FR-50 前提）なので **repo diff / FR-50 指紋に影響しない**（monitor の fingerprint ゲートを
汚さない＝いつ note を書いても re-council を誘発しない。これが plan/ 配下ではなく .flywheel/
配下に置く理由）。フォーマットは improvements.md / monitor-verdicts.csv と同系統の
`- [ISO8601] text` 1行形式。

既存の state.json `.notes` フィールド（/add の軽量 grill が詰めた Boundary/曖昧点の種）とは
**別物**。`.notes` は goal 開始時に1回書かれる design の種、`notes.md` は goal 進行中に
随時追記する作業ログ。status 表示でも別行として区別する（後述）。

### 2. 共有ヘルパー `fw_notes_tail <n>`（hooks/lib/common.sh）

greeter・status の両方が「最新 N 件」を要るので共通化する:

```bash
# .flywheel/notes.md の末尾 N 件を返す（無ければ空。tail は最新が末尾＝tail -n がそのまま最新）。
fw_notes_tail() {
  local n="${1:-3}"
  [[ -f "$FW_DIR/notes.md" ]] && tail -n "$n" "$FW_DIR/notes.md"
}
```

### 3. greeter 同梱（hooks/session-greeter.sh）

`fw_state_exists` の active 分岐（既に `evolve_line`/`heartbeat_line` と同様の任意行パターンが
ある）に notes 行を追加。**最新3件固定**（grill 確定）:

```bash
notes_line="$(fw_notes_tail 3 || true)"
```

`emit` の本文末尾に `${notes_line:+
  📝 直近のnote:
$notes_line}` を追加（evolve_line/heartbeat_line と同じ「空なら何も出さない」条件展開）。

### 4. status 表示（bin/flywheel `status)` ケース）

`_notes`（design の種）表示の直後に、notes.md の**全件**を追加表示（status はオンデマンドの
深掘りなので greeter の3件制限は適用しない）:

```bash
if [[ -f "$FW_DIR/notes.md" ]]; then
  echo "notes.md:"
  sed 's/^/  /' "$FW_DIR/notes.md"
fi
```

### 5. ライフサイクル: done / 次 goal 開始で plan/archive へ退避

`fw_archive_plan`（common.sh）を拡張: 早期 return 条件に notes.md の存在を追加し、
存在すれば archive dir へ `mv`（design.md/requirements.md と同じ「移動して原本を消す」扱い＝
次 goal は空の notes.md から始まる）。state.json は既存どおり `cp`（別ライフサイクル）のまま
変更しない。

```bash
fw_archive_plan() {
  local plandir="$FW_ROOT/plan"
  [[ -f "$plandir/design.md" || -f "$plandir/requirements.md" || -f "$FW_DIR/notes.md" ]] || return 0
  ...(既存の ts/dest/mkdir は不変)...
  for f in requirements.md design.md; do
    [[ -f "$plandir/$f" ]] && mv "$plandir/$f" "$dest/"
  done
  [[ -f "$FW_DIR/notes.md" ]] && mv "$FW_DIR/notes.md" "$dest/notes.md"
  [[ -f "$FW_STATE" ]] && cp "$FW_STATE" "$dest/state.json"
  printf '%s\n' "$dest"
}
```

`fw_archive_plan` は既に3箇所（`_start_goal` 冒頭・loop-driver done 分岐・plan-approved）から
呼ばれており、reset 経路も「次 goal 開始時に `_start_goal:78` が archive」で同様に清算される
（既存 FR-12 の仕組みをそのまま転用・新規呼び出し箇所は増やさない）。

## Boundary（触る範囲）

- `bin/flywheel`: `note)` ケース新規 + usage 1行 + `status)` ケースに notes.md 表示追加。
- `hooks/lib/common.sh`: `fw_notes_tail()` 新規 + `fw_archive_plan()` の早期 return 条件と
  本体に notes.md 対応を追加。
- `hooks/session-greeter.sh`: active 分岐に notes 同梱（最新3件）。
- `test/note.sh` 新規（chain-lib 使用: state 操作ヘルパが要るため grep-lib でなく chain-lib
  を source）。
- `test/chain-lib.sh`: simplify reuse 指摘（`GREETER`/`greeter_ctx()` が heartbeat.sh と一字一句
  重複・rule-of-three）で共有ヘルパー抽出。note.sh から利用。既存 heartbeat.sh/evolve-nudge.sh
  の遡及置換は見送り（improvements.md へ退避・次にそのファイルを触る goal に同乗）。
- 出荷規約: README Changelog / ROADMAP 該当行を `✅ 実装済` に更新 / version bump **v0.8.41**
  （plugin.json / marketplace.json 2箇所）。
- 非スコープ: notes.md の編集/削除 CLI（append-only のみ・スコープ外）、dormant 時の note
  書き込み（grill 確定＝goal 進行中限定）、journal.md との統合（別レイヤーのまま）。

## 後方互換・degrade

- notes.md が無い goal（今後 note を一度も呼ばない goal）は greeter/status とも何も表示しない
  （既存の evolve_line/heartbeat_line と同じ「空なら無表示」degrade）。
- `.flywheel/` は既に gitignore 済みなので、notes.md の存在は FR-50 の指紋（`fw_impl_fingerprint`
  が読むのは repo の tracked diff のみ）に一切影響しない。**clean 記録後に note を書いても
  re-council を誘発しない**（monitor SKILL.md の既存 Gotcha「clean 後のツリーを触らない」は
  tracked ファイルの話であり notes.md は対象外・これも .flywheel/ 配下に置く理由の一つ）。
- 既存 goal（notes.md 無し）で `fw_archive_plan` が呼ばれても、早期 return 条件に
  `-f "$FW_DIR/notes.md"` が false なら従来どおり design.md/requirements.md の有無だけで判定
  （回帰なし）。

## 完了条件（eval）

```
bash test/run-all.sh
```

exit 0。`test/note.sh` が満たすべき性質:

1. **C1（append）**: `flywheel note "text"` が `.flywheel/notes.md` に `- [ISO8601] text` 形式で
   追記される。
2. **C2（dormant 拒否）**: state が無いとき `flywheel note` は exit 1 で拒否する。
3. **C3（greeter 最新3件）**: notes.md に4件書いた状態で `session-greeter.sh` の出力
   （additionalContext）に最新3件だけが含まれ、最古の1件は含まれない。
4. **C4（status 全件）**: `flywheel status` の出力に notes.md の全件が含まれる。
5. **C5（archive）**: done（または次 goal 開始）で notes.md が `plan/archive/<ts>/notes.md` に
   退避され、`.flywheel/notes.md` は消える（次 goal はクリーンな notes.md から始まる）。
6. 既存 test 全緑（run-all 集約）。

## 検証の落とし穴（前例由来）

- `fw_archive_plan` の早期 return 条件変更は、design.md/requirements.md 両方無し・notes.md も
  無しの既存回帰ケース（例: `test/chain-lib.sh` の `setup_impl`/`setup_done_ready` で plan/ を
  作らない state）で `return 0` のまま（no-op）であることを確認する。
- greeter の C3 は `fw_heartbeat_staleness`/`fw_evolve_staleness` と同じ「hook を直接呼んで
  stdout の JSON から additionalContext を jq 抽出」パターン（`test/greeter-guide.sh` 等の
  precedent）に倣う。
- notes.md の1行=1エントリという構造的前提（`tail -n`/`sed` 表示が依存）を守るため、改行だけは
  `${1//$'\n'/ }` でスペースに畳んで sanitize する（simplify altitude 指摘・実装済み）。
  ダブルクォートは greeter の `jq --arg` 経由で安全にエスケープされるため sanitize 不要
  （フル sanitize＝monitor-lens-csv 的な引用符除去等は過剰と判断・非スコープのまま）。
