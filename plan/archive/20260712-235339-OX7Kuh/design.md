# ultrawork Fable退役対応 — judge panel を全 Opus 4.8 固定へ移行

## 背景（合意済み・掘り直し不要）

Fable 5 は 2026-06-22 でプラン内包が終了し、本環境では 2026-07-13 以降利用不可
（エンタープライズ移行はしない判断。以後の運用は Sonnet 5 メイン + Opus 4.8 強モデル）。
ultrawork（v0.8.43）は canonical Workflow スクリプト内の全 agent 呼び出しを
`model: 'fable'` に固定しているため、放置すると panel の agent が全滅し
degrade フォールバック（通常の単発回答）しか動かなくなる。

方針: **「メインのモデルに関係なく常に最強可用モデルの思考品質」という設計意図を保ったまま、
固定先を fable → opus（= Opus 4.8）に差し替える。** パラメータ化（env で切替等）は
YAGNI で非採用 — 可用な最強モデルが変わったらこの1点を再度差し替える。

## 変更内容

### 1. `skills/ultrawork/SKILL.md`

- **canonical スクリプト内の `model: 'fable'` 全4箇所** → `model: 'opus'`
  （Plan / Generate / Judge / Synthesize。`agent(` 呼び出し数 4 と一致していること）
- meta.description の「Fable judge panel」→「Opus judge panel」、phases detail の
  「Fableが〜」→「Opusが〜」（4箇所）
- frontmatter description・本文・Step 2 注意書き・Gotchas の「全 Fable」「常に Fable 品質」
  「計7〜9体の Fable」「model を fable に明示」等の記述 → Opus 4.8 表記に更新
- 変更しないもの: 構成（lens 設計→並列生成→審査2体→接木統合）、degrade 3系統、
  明示トリガー限定の契約、effort（別 follow-up として ROADMAP へ）

### 2. `commands/ultrawork.md`

- description の「全 Fable」「計7〜9体の Fable」→ Opus 4.8 表記
- 本文の「全 agent が fable 固定」→「全 agent が opus 固定」

### 3. `test/ultrawork-skill.sh`

- 不変条件を「全 Fable」→「全 Opus」に差し替え:
  - `check_all_fable` → `check_all_opus` に rename、`model: 'fable'` カウント →
    `model: 'opus'` カウント
  - 混入検査の除外セットを反転: `model: '(sonnet|haiku|opus)'` →
    `model: '(sonnet|haiku|fable)'`（**fable の残骸・巻き戻りを混入として検出**する）
  - positive control fixture 2種（指定漏れ / 他モデル混入）を opus 前提に書き換え。
    混入 fixture は `model: 'fable'` を混入例に使い、退役モデルの再混入を実走で検証
  - ヘッダコメント・fail メッセージの「全 Fable」→「全 Opus」
- 検査の型（集計一致・ペア照合ではない注意書き・grep-lib・positive control 実走）は不変

### 4. version bump v0.8.44

- `.claude-plugin/plugin.json` / `.claude-plugin/marketplace.json`（2箇所）: 0.8.43 → 0.8.44
- `README.md`:
  - 冒頭 `v0.8.43 / MIT License` → `v0.8.44 / MIT License`
  - skills 一覧行（L151）の「ultrawork（全 Fable judge panel・一発回答・v0.8.43）」→
    「ultrawork（全 Opus 4.8 judge panel・一発回答・v0.8.44 で Fable→Opus 移行）」
  - Changelog に `### 0.8.44` を追加（Fable 退役の経緯・「最強可用モデル固定」の意図維持・
    test の混入検査反転を1エントリで記録）
  - **既存 Changelog（0.8.43 の「全 Fable」記述等）は歴史記録なので書き換えない**
- `ROADMAP.md`: ultrawork 行（L62）の状態列に「v0.8.44 で Fable 退役に伴い全 Opus 4.8 へ移行」
  を追記（行自体は ✅ のまま）

## 非スコープ

- ultrawork の per-stage effort 調整（Plan=medium 等）→ ROADMAP に follow-up として積む（別 change）
- モデル固定のパラメータ化 / フォールバックチェーン（YAGNI）
- README L320 等の歴史的設計メモの書き換え

## 完了条件（eval）

```
bash test/run-all.sh
```
