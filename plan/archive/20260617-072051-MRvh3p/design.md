# flywheel: /next /add スラッシュ（adopt chain の入口）— design

## 方針

adopt chain（v0.8.10）は CLI のみで、ユーザーが普段使うスラッシュに入口が無い（`/flywheel:next` /
`/flywheel:add` が未存在）。`commands/` に next.md / add.md を足し、「一気に積んで逐次起動」を
スラッシュで完結させる。`.md` のみの goal なので最初の implementing 昇格は `flywheel go`（H-1）で行う。

## File Structure Plan（task 境界の源）

- `commands/next.md`（新規）: `!`行で `flywheel next` を叩く + 起動後の phase 別案内
- `commands/add.md`（新規）: `!`行で `flywheel add $ARGUMENTS` を叩く（`--adopt` 含む）+ 逐次の案内

## Tasks（型: Boundary / Depends / Done）

- **T1 /flywheel:next** | Boundary: `commands/next.md` | Depends: - | Done: next.md が `bin/flywheel" next` を叩く
- **T2 /flywheel:add**  | Boundary: `commands/add.md`  | Depends: -（T1 と独立・並列。境界が別ファイル） | Done: add.md が `bin/flywheel" add $ARGUMENTS` を叩く

既存 `commands/start.md` / `adopt.md` と同型（YAML frontmatter + `!`行 + 案内文）。

## 完了条件（eval）

両スラッシュが存在し、対応する flywheel サブコマンドを叩く。

```
test -f commands/next.md
test -f commands/add.md
grep -q 'bin/flywheel" next' commands/next.md
grep -q 'bin/flywheel" add' commands/add.md
```

合格 = next.md / add.md が存在し、それぞれ `flywheel next` / `flywheel add` を起動する記述を持つ。
