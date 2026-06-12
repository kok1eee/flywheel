---
description: flywheel を起動して設計ゲート付きで実装する。引数=作りたいもの。eval(test/lint) はプロジェクトから自動検出。
argument-hint: "<作りたいもの>"
---

flywheel を起動します（eval は自動検出。明示したいなら後で `flywheel reset` → `flywheel start "..." --eval "..."`）。

!`FW="${CLAUDE_PLUGIN_ROOT:+${CLAUDE_PLUGIN_ROOT}/bin/flywheel}"; FW="${FW:-$(command -v flywheel)}"; if [ -n "$ARGUMENTS" ]; then "$FW" start "$ARGUMENTS"; else "$FW" status; echo ""; echo "⚠️ goal が渡されていません（サジェストから Enter だけ押すと引数なしで実行されます）"; fi`

**上の出力に「⚠️ goal が渡されていません」がある場合**: まだ start していません。ユーザーに「何を作りますか？」と1問だけ確認し、得られた goal で `"${CLAUDE_PLUGIN_ROOT}/bin/flywheel" start "<goal>"` を Bash 実行してから、以下に進んでください。

設計ゲートが有効になりました。`$ARGUMENTS` を実装するには、まず **plan/requirements.md** と **plan/design.md** を書いてください:

- 要件が曖昧なら `/flywheel:deep-interview` → `/flywheel:discovery-council`
- 要件はあるなら `/flywheel:design`
- 設計を叩くなら `/flywheel:grill`

design.md を書くと validate-plan が自動実行され、合格で実装ゲートが開きます。以後は実装 → eval(自動検出した test/lint) → polish(simplify) → 再 eval → done まで自動で回ります。

長時間の連続自律で回す場合は native の `/goal` との併用が有効です。ただし **`/goal` は UI コマンドで、モデル（あなた）からは Skill 経由で起動できない**。自分で実行を試みず、「連続自律で回すなら `/goal <この goal>` を打ってください」とユーザーに案内すること（flywheel は eval veto と steer、`/goal` はターン継続を担当する compose 関係）。
