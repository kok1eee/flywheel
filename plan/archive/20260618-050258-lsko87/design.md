# design — FR-35 / HOTL phase2: start 経路 auto-chain

## 機構

`loop-driver`（Stop hook・非対話）は stderr + exit code でしかモデルを動かせない。
adopt chain は `exit 2`（stop 拒否＝継続強制）+ steer でモデルに「次の設計をやれ」と指示する。
phase2 は start 分岐を同じ機構に寄せる: **`exit 0`（hand-back）→ `exit 2` + 新 steer**。

「人間に pop」は loop-driver が直接できないので、steer が**次ターンのモデルに AskUserQuestion を
打たせる**ことで実現する（go/no-go・判断の grill はモデルが対話的に実施）。

## 変更点

### 1. `hooks/loop-driver.sh` の start 分岐（現 216-221）

before:
```
      cat >&2 <<EOF
🛑 flywheel: done → 次は start 経路 ... 自動連鎖を止め人間に返します ...
→ plan/requirements.md と plan/design.md を書いてください ...
EOF
      exit 0   # 人間へ hand-back（HITL）
```

after（要旨・実装時に確定）:
```
      fw_log_usage "steer:start-chain"
      cat >&2 <<EOF
🔗 flywheel: done → 次は start 経路 goal（要件を一から掘る）。HOTL で連鎖します（backlog 残 N 件）。
goal: $new_goal
→ まず人間に go/no-go を1問 grill: 「この goal を今掘りますか?」。
  ・no-go → discovery せず停止。goal は loaded(designing) のまま。再開するか /flywheel:reset で破棄するか人間が決める。
  ・go    → discovery を回す（曖昧なら /flywheel:deep-interview → /flywheel:discovery-council）。
            requirements.md と design.md を draft し、design ゲート→実装→eval→done→連鎖。
⚠️ 掘る過程で出た【判断】（スコープ/トレードオフ/優先度/命名/案の選択）は self-answer せず必ず grill-me。
   self-answer してよいのは【事実】（コードを読めば分かること）だけ。迷ったら聞く側。
EOF
      exit 2   # HOTL: 止めず次の設計（go/no-go grill から）へ進ませる
```

NO_CHAIN ガード（204 行）と adopt 分岐（207-215）は不変。start 分岐だけ差し替える。

### 2. テスト

- `test/adopt-chain.sh` ケース2: start 経路の期待を更新（exit 0 → **exit 2**・pop はする・phase=designing・
  entry=start）。ラベルも「start 停止」→「start chain」に。
- `test/start-chain.sh`（新規）: phase2 固有の steer 内容を検証。
  - C1: start goal で done → **exit 2**・backlog pop・phase=designing。
  - C2: steer（stderr）に go/no-go・discovery・「判断 ... self-answer せず」マーカーを含む。
  - C3: `FLYWHEEL_NO_CHAIN=1` → pop せず **exit 0**・phase=done・backlog 残（従来 hand-back 維持）。

## Tasks

- [ ] **T1** `hooks/loop-driver.sh` start 分岐を exit 2 + 新 steer + `fw_log_usage "steer:start-chain"` に。
  Boundary: 216-221 のみ。Depends: なし。Done: start goal で run_hook が 2 を返す。
- [ ] **T2** `test/start-chain.sh` 新規（C1-C3）。Boundary: test/。Depends: T1。Done: 単体で全 PASS。
- [ ] **T3** `test/adopt-chain.sh` ケース2 期待値更新。Boundary: test/ 既存。Depends: T1。Done: 全 PASS。
- [ ] **T4** ROADMAP の HOTL epic「start 経路 auto-chain」を ✅ 実装済（v0.8.16）に。Boundary: ROADMAP.md。Depends: T1-T3。

## 完了条件（eval）

3ケースの start-chain.sh と、退行防止の adopt-chain.sh の両方が緑であること。

```bash
bash test/adopt-chain.sh && bash test/start-chain.sh
```
