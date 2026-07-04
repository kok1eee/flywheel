# design: テスト基盤整理（FR-56・with_readonly ヘルパ + heartbeat phase ゲート演習 + guide 注記）

## 背景・問題

1. 「chmod → 実行 → chmod 戻し → assert」の observation-only 演習イディオムが 3 箇所
   （monitor-lens-csv C4/C8・heartbeat C4）に verbatim コピーされ rule-of-three 到達
   （FR-55 simplify 指摘）。しかも現状は **assert 失敗（fail=exit 1）が chmod と復元の間で起きると
   fixture が read-only のまま残る**穴がある（trap 未使用。mktemp の EXIT trap の rm -rf が
   read-only dir で静かに失敗し /tmp にゴミが残る）。
2. `fw_heartbeat_staleness` の phase ゲート（implementing/eval/polish のみ warn）は
   implementing の 1 分岐しか演習されておらず、case 文の typo リグレッションを CI が拾えない
   （FR-54 council low note）。
3. 2.1.200 で AskUserQuestion の自動継続（idle timeout）が廃止され、無人 chain では
   grill / add / discovery-council の質問が**恒久ブロック**になり得るが、guide に注記が無い。

## 方針

### 1. `with_readonly`（test/chain-lib.sh に新規ヘルパ）

```bash
# with_readonly <path> <mode> <cmd...>: path を <mode> に chmod して cmd を実行し、元の mode に
# 復元してから cmd の exit code を返す（採用形＝chain-lib の実装と同一）。
with_readonly() {
  local path="$1" mode="$2" orig rc=0; shift 2
  orig="$(stat -c %a "$path")" || return 1
  chmod "$mode" "$path" || return 1
  "$@" || rc=$?
  chmod "$orig" "$path"
  return "$rc"
}
```

- **異常系の復元は EXIT trap で**: `trap ... RETURN` は関数ローカルで fail()（exit 1）を拾えない
  ため、ヘルパ内 trap は採用しない。chain-lib の既存 EXIT trap（rm -rf $TMP）に
  `chmod -R u+w "$TMP"` を前置し、**二段構え**（正常系=ヘルパ内復元 / 異常系=EXIT trap の一括 u+w）
  で「fail 中断で fixture が read-only のまま残り掃除が失敗する」穴を塞ぐ。
- 呼び替え 3 箇所: monitor-lens-csv **C4**（dir 555）/ **C8**（file 444）/ heartbeat **C4**（dir 555）。
  各ケースの assert 内容は不変（挙動を変えない純リファクタ + 復元保証の追加）。
- chain-lib は「source 副作用あり」系の共有ハーネス。grep-lib 系テストは触らない。

### 2. heartbeat phase ゲートの分岐演習（test/heartbeat.sh に追加）

- C6: `state.phase` を jq 直編集（chain-lib precedent）で **spec-ready** に → heartbeat 欠如でも
  greeter が**無音**（designing/spec-ready は未発火が正常）。
- C7: phase を **eval** に、C8: **polish** に → heartbeat 欠如で **warn**（case 文の 3 値を個別に踏む）。
- 既存 C1-C5 は不変。

### 3. guide への注記（skills/guide/SKILL.md の「Gotchas」節に 1 項）

2.1.200 で AskUserQuestion が自動継続しなくなった（idle timeout は /config でオプトイン）。
無人 chain（spawn-session の flywheel 駆動等）では grill / add / discovery-council の質問で
恒久ブロックし得る。回避: ①無人運用は /config で idle timeout をオプトイン、②adopt 経路で
判断を notes に焼き込み質問レス化（判断は積む前の対話で済ませる）。

## polish（simplify レビュー採択）

- chain-lib に `jq_patch <file> <jq-args...>` を追加（「jq → tmp → mv」イディオムの 6 回目コピペを
  この diff 自身が足していた Reuse 指摘）。diff 内の使用箇所（setup_impl / setup_done_ready /
  heartbeat C6-C8）を呼び替え。diff 外の 4 箇所（polish-monitor-fuse ×2 / verification-merge /
  monitor-fingerprint の set_monitor_raw）は improvements.md へ退避。
- heartbeat C6-C8 の for-case ループをフラット逐次ブロックに変更（C1-C5 と書式統一・分岐が非一様で
  ループ化の重複排除効果が無かった）。
- design.md のコードサンプルを採用形に一本化（trap RETURN 案を提示→注記で撤回する二段構成を解消）。

## Boundary（触る範囲）

- `test/chain-lib.sh`（with_readonly + EXIT trap に chmod -R u+w 前置）
- `test/monitor-lens-csv.sh`（C4/C8 呼び替え）/ `test/heartbeat.sh`（C4 呼び替え + C6-C8 追加）
- `skills/guide/SKILL.md`（Gotchas 1 項）
- 出荷規約: README Changelog / ROADMAP（FR-56 行）/ version **v0.8.37**（plugin.json / marketplace.json / README 冒頭）
- 非スコープ: grep-lib 系テストへの適用（chmod 演習が無い）、adopt chain の着手前 checkpoint
  （goal C・別途 grill）、AskUserQuestion 対応の機構実装（注記のみ）

## 後方互換・degrade

- 純リファクタ + テスト追加 + docs のみ。hook / CLI のロジック変更なし。
- with_readonly は chain-lib を source する既存テストの名前空間に関数を 1 つ足すだけ
  （既存名と衝突しないことを grep で確認して実装）。

## 完了条件（eval）

```
bash test/run-all.sh
```

exit 0。満たすべき性質:

1. monitor-lens-csv C4/C8・heartbeat C4 が with_readonly 経由になり、既存 assert が全て緑のまま
   （挙動不変の純リファクタ）。
2. **復元保証の実証**: with_readonly の cmd が非ゼロでも path の mode が復元されることを
   chain-lib 内 or いずれかのテストで 1 assert（fail 中断時の EXIT trap u+w は…テスト自身の
   fail を演習できないため、正常系の「非ゼロ cmd 後に mode 復元」のみ実走で assert）。
3. heartbeat C6（spec-ready 無音）/ C7（eval warn）/ C8（polish warn）が追加され緑。
4. guide の Gotchas に AskUserQuestion 注記が存在する。
5. 既存 test 全緑（run-all 集約）。

## 検証の落とし穴（前例由来）

- `trap ... RETURN` は関数ローカルで fail(exit) を拾えない → 異常系は chain-lib の EXIT trap に
  `chmod -R u+w "$TMP" 2>/dev/null` を前置する二段構えで担保（上記）。
- stat は GNU（`-c %a`）で統一（CI=ubuntu / 本番=AL2023 とも GNU coreutils）。
- phase の jq 直編集は test harness の特権（C-2 はモデルの直編集禁止であってテストは対象外・
  setup_impl の既存 precedent）。
