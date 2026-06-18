# requirements — FR-38: polish+monitor steer の融合（往復削減）

## 背景

done 前ゲートは polish(simplify) と monitor council の2段。現状の loop-driver は
`enter_polish` が `exit 2` で monitor ゲート手前で抜けるため、`simplify(stop) → monitor(stop) →
done` と**毎段で停止→Stop hook→再開のハンドシェイク**を挟む（3往復）。polish が走る goal では
この往復が体感 latency。

## やること

polish が要るとき、**1本の steer で「simplify→monitor を同じターンで」実行**させ、monitor を
pending に prime する。次停止で eval緑 + monitor verdict を一括判定 → done（2往復）。

**逐次パイプラインであって並列ではない**: monitor は simplify 後の最終コードを検証するので
順序 simplify→monitor は固定（並列にすると古いコードを検証して無効）。融合が削るのは段間の
停止ハンドシェイク1回分だけで、挙動の中身は不変。

## 安全性（コードで裏取り済み）

- **eval は毎停止で独立に回る**ので、simplify が eval を壊しても次停止の eval-fail 分岐が拾い
  monitor verdict を破棄して bounce ＝ **done をすり抜けない**。
- model が steer の monitor 部分を飛ばしても、monitor=pending を prime してあるので**次停止の
  monitor pending 分岐が拾って再 steer**＝従来挙動に安全に degrade（往復が1回戻るだけ）。
- monitor ゲート本体（loop-driver の clean/drift/pending 分岐・cap）は**不変**。融合は steer の
  束ね方と pending prime だけ。

## 決定（grill 済み・2026-06-18）

- **デフォルト ON**（polish が走る全 goal で融合）。`FLYWHEEL_NO_FUSE=1` で従来の分離2ステップに
  戻すエスケープハッチ（`FLYWHEEL_NO_CHAIN` と同パターン）。

## スコープ

- IN: `hooks/loop-driver.sh` の **main eval-green 経路の polish 呼び出し（line 110 周辺）** + test/。
- OUT: `eval_cmd` 未設定経路の polish（line 90・monitor 無関係なので触らない）/ monitor ゲート本体 /
  monitor council の中身（observer fan-out）/ polish を skip する小 diff goal（融合の出番なし）。

## 完了条件

- 融合 ON（既定）: polish 必要時に exit 2 + monitor=pending prime + steer に simplify と monitor 両方。
- `FLYWHEEL_NO_FUSE=1`: 従来どおり simplify のみ steer・monitor を prime しない。
- 既存テスト（adopt-chain / start-chain / eval-veto-hint / polish-rename-skip 等）に退行なし。
