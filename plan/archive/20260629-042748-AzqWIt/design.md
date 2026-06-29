# design — monitor verdict 再利用（軽量化・改善C / FR-50）

## 背景

監視 council（3 observer fan-out）は done 前の最重量オペで 529 被弾源。grill で **verdict 再利用（無変更時）**
を選択（gate を一切弱めない安全な軽量化）。あわせて**現状の穴**を塞ぐ: clean 記録後にモデルが
コードを変えても、次停止の clean ゲートは（eval さえ緑なら）done をすり抜けさせる（monitor は
再検証しない）。これは「clean を tree fingerprint に紐付ける」ことで軽量化と穴塞ぎを同時に達成できる。

**不変条件**: gate の独立性・客観性は不変。verdict 再利用は「**同じコード＝同じ結論**」の安全な省略のみ。
self-grade 化しない（再利用は monitor が一度下した独立 verdict をそのまま使うだけ）。

## 何を作るか（ファイル/関数レベル）

### 1. `hooks/lib/common.sh` に `fw_impl_fingerprint`

作業ツリーの実装 diff の指紋（sha256）。`monitor=clean` をこの指紋に紐付ける。

```bash
fw_impl_fingerprint() {
  local base d
  base="$(fw_baseline_rev)"; [[ -n "$base" ]] || return 0
  # baseline 累積（fw_repo_diff_lines と同規約）。plain jj diff だと commit でゼロリセットする罠を回避。
  d="$( cd "$FW_ROOT" 2>/dev/null && { jj diff --from "$base" --git 2>/dev/null || git diff "$base" 2>/dev/null; } )" || true
  [[ -n "$d" ]] && command -v sha256sum >/dev/null 2>&1 || return 0   # baseline無/diff空/VCS不能 → 空指紋
  printf '%s' "$d" | sha256sum | awk '{print $1}'
}
```

- `.flywheel/`（gitignore 済み）は diff に出ない＝**state 変更で指紋が揺れない**（本番 jj / git どちらも）。
- VCS 不能・diff 空なら**空指紋**を返す。記録も gate も空なら「指紋未記録」扱いで**後方互換 done**（VCS 不能環境は pre-C 挙動に degrade）。記録時は指紋あり・gate 時に取得不能なら**不一致＝再検証**に倒れる（fail-closed の主経路）。

### 2. `bin/flywheel` の `monitor-set`: clean のとき fingerprint を保存

`{status, level, reason, ts}` に **`fingerprint`** を足す。clean のときだけ `fw_impl_fingerprint`、
drift/pending は空。（CLI の state 書き込みは C-2 対象外。）

### 3. `hooks/loop-driver.sh` の clean ゲート（現 `elif [[ "$mstatus" == "clean" ]]`）

「clean → 無条件 done」を **「指紋一致なら done / 不一致なら再 council」** に変える:

```
mfp="$(fw_get '.monitor.fingerprint')"; cur_fp="$(fw_impl_fingerprint)"
if [[ -z "$mfp" || "$mfp" == "$cur_fp" ]]; then
   …done…                       # 指紋未記録(legacy/test) or 一致(無変更) → done
else
   …monitor を pending に戻し steer:monitor を記録…  # 変更後の未検証コード → 再 council（fail-closed）
fi
```

cap 執行（council が verdict を記録しない失敗）は**次停止の pending 枝**に委ねる（stale 枝で
`monitor_bump` を二重に書かない）。持続的に「clean 記録→コード変更」を繰り返す病的振動は、
いずれ drift verdict になり drift 枝の cap が拾う＝間接 backstop。

```
```

- **後方互換**: `mfp` 空（指紋未記録＝既存テストや旧 verdict）は従来どおり done。本番 `monitor-set clean`
  は常に指紋を付けるので、本番の clean は必ず指紋検証される（穴は本番で閉じる）。
- 再 council 枝は monitor を pending に戻し `steer:monitor` を記録するのみ（cap 執行は次停止の
  pending 枝に委ね、再 prime/escalate を二重に書かない）。

### 4. `test/monitor-fingerprint.sh`（`test/chain-lib.sh` を source）

temp git リポは tracked な `seed.txt` を変更して非空指紋を作る（`.flywheel` は untracked で git diff に出ない）:

- **C1**: `seed.txt` 変更 → `monitor-set clean` → `state.monitor.fingerprint` が非空。
- **C2 一致**: 上記後、コード不変で `run_hook`（eval=true 緑・polished）→ 指紋一致 → **phase=done**。
- **C3 不一致**: `monitor-set clean` 後に `seed.txt` を追加変更 → `run_hook` → 指紋不一致 → **done にならず** monitor=pending に戻る（stale clean すり抜け阻止）。
- **C4 後方互換**: `monitor` を `{status:clean}`（指紋なし）に直接セット → `run_hook` → 従来どおり done。

## 非スコープ

- **multi-repo（FR-B の宣言 sibling）の指紋は含めない**（v1 は FW_ROOT のみ）。sibling 変更後の stale clean は
  塞がらない＝既知の限界として明記（multi-repo は稀・council は通常1回は走る）。
- post-drift の単一 observer 化・diff サイズ可変（grill の選択肢 b/c）は不採用（gate を薄めるため）。

## 完了条件（eval）

```
bash test/run-all.sh
```

`test/monitor-fingerprint.sh`（C1–C4）が自動登録され、既存全スイート（特に polish-monitor-fuse /
start-chain / adopt-chain の clean→done 系）と共に緑であること。
