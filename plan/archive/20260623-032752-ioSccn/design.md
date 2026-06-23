# design: intent-router（legacy auto-engage）の削除（FR-45）

adopt（結晶化）。`FLYWHEEL_AUTO=1` の auto-engage hook を撤去する。plan route（Shift+Tab）が
上位互換で README 自身が「凍結」と書いており、毎プロンプト発火する常駐 hook を1つ減らす。

## 背景（なぜ）

intent-router は「build 意図の prompt を検知して flywheel を自動 start する」**legacy auto-engage
hook**（`UserPromptSubmit`・opt-in `FLYWHEEL_AUTO=1`）。plan route が完全な上位互換になり README で
凍結済み。`session-greeter.sh` が deprecated 経路を併記する矛盾も残る。常時走る自動機構の残骸なので削る。

## 変更点（hooks/ から完全撤去 — eval が grep で検証）

1. **`hooks/intent-router.sh` を削除**（ファイルごと）。
2. **`hooks/hooks.json`**:
   - `description` から `+ intent-router` を除去。
   - `UserPromptSubmit` の hooks 配列から intent-router エントリを削除（**plan-steer は残す**）。
3. **`hooks/session-greeter.sh`**:
   - 先頭コメントの `FR-15 intent-router` 参照を除去（意味＝state を作らない・思い出させるだけ、は不変）。
   - `FLYWHEEL_AUTO` を勧めるコメント行を削除。
   - dormant 案内の `FLYWHEEL_AUTO` if 分岐（`auto_line`）を削除し、emit から `${auto_line}` 行を除去。
4. **`hooks/lib/common.sh`**: コメントの `auto-engage(intent-router)` 参照を除去（fw_init の chokepoint
   説明から auto-engage を外す）。

## 変更点（docs — changelog 履歴は残す）

5. **`README.md`**: hook 表の `intent-router` 行（L120）と env 表の `FLYWHEEL_AUTO` 行（L143）を削除。
   Changelog 内の歴史的言及（FR-15 等）は**残す**。
6. **version bump → v0.8.25**: `plugin.json` + `marketplace.json`（2箇所）、README 冒頭 + Changelog、
   ROADMAP:60 を `✅ 実装済（v0.8.25・FR-45）` に。

## 変更点（test — 恒久回帰ガード）

7. **`test/intent-router-removed.sh`**（新規）: `hooks/intent-router.sh` 不在 + `hooks/` に
   `intent-router|FLYWHEEL_AUTO` 参照ゼロを assert。CI（run-all.sh）に乗せて再混入を防ぐ。

## 非スコープ

- hooks.json の配線除去は**次セッション再起動で完全反映**（現セッションは旧 hooks.json をキャッシュし得る）。
- Changelog の歴史記述・他 hook・FLYWHEEL_PLAN（plan route）は不変。

## 完了条件（eval）

```bash
bash test/run-all.sh
```
