---
description: flywheel を起動して設計ゲート付きで実装する。引数=作りたいもの。eval(test/lint) はプロジェクトから自動検出。
argument-hint: "<作りたいもの>"
---

flywheel を起動します（eval は自動検出。明示したいなら後で `flywheel reset` → `flywheel start "..." --eval "..."`）。

!`flywheel start "$ARGUMENTS"`

設計ゲートが有効になりました。`$ARGUMENTS` を実装するには、まず **plan/requirements.md** と **plan/design.md** を書いてください:

- 要件が曖昧なら `/flywheel:deep-interview` → `/flywheel:discovery-council`
- 要件はあるなら `/flywheel:design`
- 設計を叩くなら `/flywheel:grill`

design.md を書くと validate-plan が自動実行され、合格で実装ゲートが開きます。以後は実装 → eval(自動検出した test/lint) → polish(simplify) → 再 eval → done まで自動で回ります。

長時間の連続自律で回す場合は、native の `/goal` にもこの goal を張ってください（flywheel は eval veto と steer、`/goal` はターン継続を担当する compose 関係）。
