---
description: 会話 or handoff(journal)で合意済みの実装方針を flywheel に載せる。designing の「掘る」をスキップして design.md に結晶化し、validate→implementing へ。
argument-hint: "<一言サマリ（省略可。省略時は journal の最新 Next を使う）>"
---

会話 or handoff の合意を flywheel に載せます（adopt・FR-29）。要件をゼロから掘り直さず、**既に合意した方針を design.md に結晶化**します。

!`if [ -n "$ARGUMENTS" ]; then "${CLAUDE_PLUGIN_ROOT}/bin/flywheel" adopt "$ARGUMENTS"; else "${CLAUDE_PLUGIN_ROOT}/bin/flywheel" adopt "(会話/journal の合意を結晶化)"; fi`

設計ゲートが有効になりました（phase=designing）。次に **plan/design.md を結晶化**してください:

1. **source を決める**（優先順）:
   - このセッションの会話で合意した実装方針があれば、それを使う
   - 無ければ `.claude/journal.md` の**先頭エントリの Next Actions**（直近の handoff）を Read して使う
2. **plan/design.md を書く**。要件を掘り直す必要はありません（合意は既にある）。design.md には最低限:
   - 何を作るか（合意した方針を具体的に。ファイル名・関数名レベルで）
   - **`## 完了条件（eval）`** セクション（必須）— done を機械判定する fenced code block（例: ```\nuv run ruff check . && uv run pytest\n```）
3. design.md を書くと **validate-plan が自動実行**され、合格で実装ゲートが開きます。完了条件セクションが無い・形式不備なら差し戻されます

合格後は実装 → eval(test/lint) → polish(simplify) → 再 eval → done まで自動で回ります。

**注意**:
- adopt は「合意済み」前提です。会話にも journal にも合意が無い場合は、結晶化せず `/flywheel:start` で designing から掘り直してください（`flywheel reset` で adopt state を破棄してから）。
- 長時間の連続自律で回すなら native `/goal` を併用してください（`/goal` は UI コマンドで、モデルからは起動できません。「`/goal <この goal>` を打ってください」とユーザーに案内すること）。
