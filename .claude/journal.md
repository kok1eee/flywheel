# Journal

> セッション間の引き継ぎ。最新が上。Recap を時系列アーカイブとして保持し、
> 次のアクションを明示する。詳細なセッション内要約は built-in `/recap` も併用。

## 2026-06-13 08:58 [ip-10-0-67-244]

### Recap
v0.5 系を3リリース実装・push・install 済み（plugin は 0.5.2、要再起動）。v0.5.0 = plan-mode route（plan-steer/plan-gate/plan-approved の3 hook。ExitPlanMode の計画テキストを検証し、承認の瞬間に hook が plan/design.md へ artifact 化 + 完了条件を eval_cmd 昇格 + implementing へ。engage は FLYWHEEL_PLAN=1 opt-in）。v0.5.1 = kakuduke 実戦レビューで発覚した C-2 違反（モデルが `flywheel _advance done` で eval 判定を迂回）への enforcement（`_advance` は FLYWHEEL_HOOK=1 必須・`.flywheel/` への Edit/Write を design-gate が全 phase ブロック）+ evolve の計測データ読み先修正（本番 CSV は `~/.claude/plugins/data/flywheel-kok1eee-flywheel/`）。v0.5.2 = veto loop に進捗方向（fail 数の前回比で 📉続行/➡️別仮説/📈revert 規律を steer）。autoresearch plugin は計測データ（使用0回）を根拠に棚卸し→学び2点だけ improvements.md に吸収→削除済み。kakuduke 実戦では FR-19（spec-designed eval）が本番初動作（eval_src=spec、designing→done 46分）。

### Next
- README.md を v0.5.2 の全体像で再構成する: plan-mode route（Shift+Tab → 承認 → 自動 loop）を主経路として冒頭に据え、CLI route（flywheel start）を従に。hook 8個の表・環境変数 5個（FLYWHEEL_OFF/PLAN/VETO_CAP/EVAL_TIMEOUT/POLISH_MIN_DIFF）・FR-25 までの機能を反映。肥大化した Changelog の整理（古い版は折りたたみ or 要約）も検討
- ユーザーの shell rc に `export FLYWHEEL_PLAN=1` を追加（plan route の常用化。未実施）
- 次の実戦 goal で確認: done の history が `loop-driver: eval pass` で刻まれるか（v0.5.1 の C-2 ガード効果）/ eval 失敗時に 📉📈 の方向表示が出るか（v0.5.2）
- 将来候補（spec 記載済み）: FR-3 headless 分岐（grill↔critic）、eval の挙動検証（verification 統合）、FLYWHEEL_PLAN の default 化判断（dogfood 後）
