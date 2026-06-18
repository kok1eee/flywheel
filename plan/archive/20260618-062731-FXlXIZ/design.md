# design — 初回 eval veto で command-not-found を検出したら set-eval を促す

## 背景

eval_cmd 自体が壊れている（コマンド名ミス・未インストール・パス誤り）と、eval が毎回
`command not found` / `No such file or directory` で落ち、loop は「コードを直せ」と steer し続ける。
だがコードは悪くない＝直すべきは eval_cmd。長い迂回になる。最初の veto で原因を示唆して短絡する。

## 機構（コードで裏取り済み）

`hooks/loop-driver.sh` の eval 失敗分岐（rc != 0・240-276）:
- 246-249 `bump_veto_or_handoff`: veto cap 到達なら hand-back（exit 0）。
- 251-252 `$hint`（polish 由来）/ 254-267 `$trend`（fail 数の方向）。
- 270-275 継続 steer（`$hint$trend` を差し込む）→ 276 `exit 2`。

非 cap 失敗のたびに 271 の steer が出る＝**最初の veto でも出る**。ここに command-not-found
ヒントを足すのが素直（cap 到達の hand-back 経路は触らない＝スコープ最小）。

## 変更点

### 1. `hooks/loop-driver.sh`（eval 失敗分岐）

`$trend` 算出の近くで、eval 出力 `$out` が **eval_cmd 不在シグナル**にマッチするか判定し
`$cmd_hint` を作る。271 の steer 行に `$cmd_hint` を追加する。

- 検出パターン: **shell プレフィクス付き**の解決失敗だけに絞る（裸の `No such file or directory` /
  `: not found` は通常のテスト失敗出力にも現れ誤検知するため）。
  `(^|/)(bash|zsh|sh|dash|ash): .*(command not found|No such file or directory|: not found)`
  （eval は `bash -c` 経由なので解決失敗は `bash:` プレフィクスで出る。app 出力の `config.yml: No
  such file...` は弾く）
- ヒント文（例）: ` ⚠️ eval_cmd が解決できていない可能性（command not found 系）。コードでなく eval_cmd の指定ミスなら 'flywheel set-eval "<正しいコマンド>"' で直せます。`

通常のテスト失敗（assert 落ち・exit 1 で出力に上記パターン無し）には付けない。

### 2. `test/eval-veto-hint.sh`（新規）

`test/chain-lib.sh` を source（mktemp git リポ + state ヘルパを再利用）。`setup_done_ready` は
eval_cmd を `true` 固定なので、本テスト用に **任意 eval_cmd で implementing 状態を作る** ローカル
ヘルパ `setup_impl <eval_cmd>` を定義（`flywheel start --eval "<cmd>"` → jq で phase=implementing /
polished=true）。veto cap 未満で初回失敗の steer に届くこと（fresh start は veto=0）。

- **C1**: eval_cmd = 不在コマンド → stderr に `set-eval` ヒント**有**・exit 2。
- **C2**: eval_cmd = `false`（出力なしで rc=1＝通常失敗）→ ヒント**無**。
- **C3**: eval_cmd が紛らわしい文字列を出力する通常失敗（`echo 'config.yml: No such file...'; exit 1`）
  → ヒント**無**（誤検知の回帰ガード。広い grep だと誤発火していた）。

## Tasks

- [ ] **T1** `hooks/loop-driver.sh` に `$cmd_hint` 検出 + 271 steer へ差し込み。Boundary: eval 失敗分岐のみ。Done: C1 で steer に set-eval が出る。
- [ ] **T2** `test/eval-veto-hint.sh` 新規（C1/C2）。Boundary: test/。Depends: T1。Done: 単体で全 PASS。

## 完了条件（eval）

command-not-found には set-eval ヒントが出て、通常のテスト失敗には出ないこと。

```bash
bash test/eval-veto-hint.sh
```
