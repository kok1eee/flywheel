# design — polish 比例制御: git fallback に rename 検出（-M）

## 機構

`fw_repo_diff_lines`（`hooks/lib/common.sh:100-119`）は `jj diff --stat` を試し、失敗時は
`git diff --stat "$base"` に fallback して per-file の変更行を合算する。jj は rename を既定検出
（pure rename = 0 行）。git fallback は `-M` 無しのため `diff.renames=false` 環境で rename が
delete+add に分解され 2×N 行に膨らむ。→ git fallback に `-M`(--find-renames) を足して config
非依存で rename を collapse させる。jj path は変更しない。

## 変更点

### 1. `hooks/lib/common.sh`（`fw_repo_diff_lines` git fallback・104行）

```
out=$(cd "$root" && git diff --stat "$base" 2>/dev/null) || { printf '0\n'; return; }
```
→
```
out=$(cd "$root" && git diff -M --stat "$base" 2>/dev/null) || { printf '0\n'; return; }
```

`-M`(=`--find-renames`) で rename を1エントリ（変更行のみ）に collapse。`-C`(copy) は足さない
（コピー＝重複＝simplify 対象なので skip させない）。

### 2. `test/polish-rename-skip.sh`（新規）

git-only の temp リポ（`jj diff` が失敗し git fallback を踏む）で `fw_repo_diff_lines` を直接検証。
`set -e` の混入を避けるため common.sh は **subshell で source** し関数の stdout だけ取る。
`diff.renames=false` を設定して「修正が効いている」ことを確実にする。

- **C1**: `diff.renames=false` + 40 行ファイルを rename → `fw_repo_diff_lines` が `< 30`（≈0）。
  （`-M` 無しなら ~80 行になる＝この差で修正を検出）
- **C2**: rename でない純粋な内容追加（40 行追記）→ `fw_repo_diff_lines` が `>= 30`
  （real change を誤抑制しない回帰ガード）。

## Tasks

- [ ] **T1** `hooks/lib/common.sh` git fallback に `-M`。Boundary: 104行のみ。Done: C1 が ≈0。
- [ ] **T2** `test/polish-rename-skip.sh` 新規（C1/C2）。Boundary: test/。Depends: T1。Done: 単体で全 PASS。

## 完了条件（eval）

rename は collapse（min 未満）し、純粋な内容追加は従来どおり数えること。

```bash
bash test/polish-rename-skip.sh
```
