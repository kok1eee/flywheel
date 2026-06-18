# drift steer の文言明確化 — design

## 背景

monitor の drift verdict は loop-driver が読んだ瞬間に `monitor=null` にクリアし（`loop-driver.sh:150`）、
implementing に差し戻して steer する。だが monitor council が drift を記録した**後**にモデルが先回りで
修正すると、次の停止で loop-driver が「修正前に記録された drift」を初回執行 → 「🔁 drift を検知しました、
修正して」（`loop-driver.sh:177-178`）が空振りに見え、「**古い verdict を読み続けるバグ？**」と誤解される
（実運用で発生）。実際は `L150` でクリア済みで、修正後の次の停止で再 monitor が走る正常動作。

## 方針

`loop-driver.sh` の drift implementing steer（L177-178）に、この事実を1行明示する:
**「この verdict は処理済み・クリア済み。修正したら次の停止で自動的に再 monitor が走る（古い verdict を
読み続けない）」**。挙動は不変（steer 文言の追加のみ）。Boundary は `hooks/loop-driver.sh` の drift steer だけ。

## 完了条件（eval）

```
bash -n hooks/loop-driver.sh
grep -q '再 monitor が走' hooks/loop-driver.sh
```

合格 = loop-driver.sh の構文 OK・drift implementing steer に「再 monitor が走る」明示文言がある。
