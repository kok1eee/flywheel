#!/usr/bin/env bash
# loop-driver (Stop hook) — FR-5, FR-6, FR-9, FR-11
# 継続そのものは native /goal に任せる（C-1: Stop hook の連続 cap を避ける）。
# この hook は「eval veto + polish 挿入」に徹する:
#   implementing → eval（ty/ruff/test の CLI 判定）→ 初回合格で polish（simplify を steer, FR-11）
#   → 再 eval → done。未達なら implementing に戻して veto。
#
# polish は「初回 eval 合格後」に goal につき1回だけ（v0.4.2 / polish-on-green）:
#   修正ループに polish が挟まらず（turn 最短）、磨く対象は修正込みの最終形、
#   green 起点なので polish 後の再 eval 失敗は simplify が犯人と確定できる。
# eval は test/build/型/lint の exit code のみで決定論判定（M-1）。挙動検証(LLM)は将来。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

fw_hook_guard || exit 0

# phase/eval_cmd/veto_count/polish/polished を1回の jq で取得（Stop hook は毎ターン走るので fork を抑える）
# 区切りは Unit Separator(0x1F)。タブ等の whitespace は read が空フィールドを畳んでズレるため使わない。
IFS=$'\037' read -r phase eval_cmd veto polish polished < <(
  jq -r '[.phase // "", .eval_cmd // "", .veto_count // 0,
          (if .polish == null then true else .polish end),
          (.polished // false)] | map(tostring) | join("\u001f")' "$FW_STATE"
)
# done / no-spec / designing（grill 人間待ち = FR-9 停止点b）→ stop 許可
fw_work_active "$phase" || exit 0

cap="${FLYWHEEL_VETO_CAP:-${CLAUDE_CODE_STOP_HOOK_BLOCK_CAP:-8}}"
veto="${veto:-0}"

# veto を1加算し、cap 到達なら理由付きで stop を許可して人間に返す（FR-10）。
# 使い方: bump_veto_or_handoff "<cap 到達時のメッセージ>" && exit 0（cap 到達時のみ 0 を返す）
bump_veto_or_handoff() {
  veto=$((veto + 1))
  fw_set_json veto_count "$veto"
  if [[ "$veto" -ge "$cap" ]]; then
    fw_advance implementing "loop-driver: veto cap $cap 到達 — 人間介入が必要"
    echo "🛑 flywheel: veto が $cap 回に達したので人間に返します。$1" >&2
    return 0
  fi
  return 1
}

# 監視ゲート専用カウンタ（FR-30）。eval veto は緑ごとに L97 で 0 リセットされるため、緑領域を
# 回る監視ループ（pending churn / drift-impl 反復）には人間 hand-back cap が効かない（eval-fail
# ループとの非対称）。それを埋める別系統カウンタ。返り値 0 = cap 到達（呼び出し側で hand-back）。
mcap="${FLYWHEEL_MONITOR_CAP:-${FLYWHEEL_VETO_CAP:-${CLAUDE_CODE_STOP_HOOK_BLOCK_CAP:-8}}}"
monitor_bump() {
  local n; n="$(fw_get '.monitor_attempts')"; n="${n:-0}"; n=$((n + 1))
  fw_set_json monitor_attempts "$n"
  [[ "$n" -ge "$mcap" ]]
}

# polish 段に入る（FR-11・polished フラグで goal につき1回だけ）。
# $2="monitor" のとき融合(FR-38): simplify と monitor を同一ターンで実行させ往復を 3→2 に削る。
# simplify→monitor は逐次（monitor は simplify 後の最終コードを検証するので順序固定）で、削るのは
# 段間の停止ハンドシェイクだけ。monitor を pending に prime しておくので、model が monitor を飛ばしても
# 次停止の monitor ゲート(pending 分岐)が拾って再 steer ＝ 安全に従来挙動へ degrade。eval は毎停止で
# 独立に回るので simplify が壊しても次停止の eval-fail が拾い done をすり抜けない。
enter_polish() {  # $1 = steer 冒頭文脈, $2 = "monitor" で融合
  fw_set_json polished true
  fw_advance polish "loop-driver: enter polish${2:+ +monitor}"
  fw_log_usage "steer:simplify"   # FR-18: steer 従命率の分母
  if [[ "${2:-}" == "monitor" ]]; then
    fw_set_json monitor '{"status":"pending"}'
    fw_log_usage "steer:monitor"
    cat >&2 <<EOF
$1 done の前に2つを【同じターンで・この順に】:
1) Skill: simplify でコードを整理（polish: reuse/簡素化/効率/altitude）。
2) 続けて Skill: flywheel:monitor で drift を検証（観測者 fan-out: 要件逸脱/挙動/進捗）。simplify の結果を検証するので必ず simplify の後。
次の停止で eval 緑 + monitor verdict を一括判定 → clean なら done。
EOF
  else
    echo "$1 Skill: simplify でコードを整理してください（polish: reuse/簡素化/効率/altitude）。次の停止で再度品質チェックし、通れば done です。" >&2
  fi
  exit 2
}

# polish を実施すべきか（FR-11 + FR-20 の diff 適応）。
# polish=true・未実施で、goal の累積 diff が閾値以上のときだけ 0 を返す。
# 小 diff の goal（typo 修正等）は simplify 1ターンが過剰なので skip して即 done へ。
should_polish() {
  [[ "$polish" == "true" && "$polished" != "true" ]] || return 1
  local min="${FLYWHEEL_POLISH_MIN_DIFF:-30}" n
  n="$(fw_goal_diff_lines)"
  if [[ -n "$n" && "$n" -lt "$min" ]]; then
    fw_set_json polished true   # skip も実施判断済みとして記録（再判定しない）
    echo "ℹ️ flywheel: goal の累積 diff が ${n} 行（閾値 ${min} 未満・FLYWHEEL_POLISH_MIN_DIFF）のため polish を省略します。" >&2
    return 1
  fi
  return 0   # diff が大きい or 計測不能（baseline なし）→ 従来どおり polish
}

# spec-ready のまま停止 = 門が開いたのに source 編集ゼロ。eval を回すと「未実装でも既存
# テストは green」で空振り done になり得るため、回さず実装開始を steer する（veto で cap 保護）。
# 既知の縁: Bash だけで完結する goal はここに留まる（H-1 と同根）→ FLYWHEEL_OFF=1 で逃がす。
if [[ "$phase" == "spec-ready" ]]; then
  bump_veto_or_handoff "実装が開始されていません（Bash のみで完結する goal なら FLYWHEEL_OFF=1）。" && exit 0
  echo "▶️ flywheel: 設計は合格済み（spec-ready）ですが実装がまだです。実装を開始してください。goal: $(fw_get '.goal')" >&2
  exit 2
fi

# eval_cmd 未設定 → 決定論判定できない。polish だけ1回挿入し、stop は許可（無限ブロックを避ける）。
if [[ -z "$eval_cmd" ]]; then
  should_polish && enter_polish "🪄 flywheel: 実装が一段落。"
  echo "⚠️ flywheel: eval_cmd 未設定のため done を機械判定できません。'$FW_CLI start --eval \"<ty/ruff/test>\"' で設定すると loop が完了を強制します。今回は stop を許可します。" >&2
  exit 0
fi

# eval phase へ進め、ty/ruff/test を CLI 実行（決定論）。
# - mise shims を PATH に前置: hook の非対話環境で npm/node 等が見えず eval が常に fail する事故を防ぐ
# - timeout で hook timeout(600s) より先に自前で打ち切り、silent kill（判定なしで stop が通る）を明示の veto に変換
prev_phase="$phase"
[[ "$phase" != "eval" ]] && fw_advance eval "loop-driver: enter eval"
[[ -d "$HOME/.local/share/mise/shims" ]] && export PATH="$HOME/.local/share/mise/shims:$PATH"
eval_timeout="${FLYWHEEL_EVAL_TIMEOUT:-540}"
out="$(cd "$FW_ROOT" && timeout "$eval_timeout" bash -c "$eval_cmd" 2>&1)" && rc=0 || rc=$?
[[ "$rc" -eq 124 ]] && out="⏱ eval が ${eval_timeout}s でタイムアウト。eval_cmd を軽くするか FLYWHEEL_EVAL_TIMEOUT を上げてください。
$out"

if [[ "$rc" -eq 0 ]]; then
  fw_set_json veto_count 0
  fw_set_json last_fail_count 0   # FR-25: green を baseline に（以後の悪化 = 0→N で即 revert steer）
  # 初回合格 → done の前に polish を1回（green を確認してから磨く = polish-on-green）
  # 既定では polish と monitor を1ターンに融合（FR-38）。FLYWHEEL_NO_FUSE=1 で従来の分離2ステップ。
  if should_polish; then
    if [[ "${FLYWHEEL_NO_FUSE:-}" == "1" ]]; then
      enter_polish "✅ flywheel: eval 合格（$eval_cmd）。done の前に仕上げ:"
    else
      enter_polish "✅ flywheel: eval 合格（$eval_cmd）。" monitor
    fi
  fi

  # --- monitor ゲート（FR-30）: done の前に監視 council で drift を検証する ---
  # polish 後の緑形を、実装文脈を持たない観測者で多観点検証してから done にする。
  # drift の執行はここに集約。drift フラグは Skill: flywheel:monitor が CLI（flywheel monitor-set）で書く。
  mstatus="$(fw_get '.monitor.status')"
  if [[ -z "$mstatus" ]]; then
    fw_set_json monitor '{"status":"pending"}'   # 検証要求（pending 化）
    if monitor_bump; then
      # cap 到達: 監視が収束しない（skill 不調 等）→ monitor をクリアして人間に返す。
      fw_set_json monitor null; fw_set_json monitor_attempts 0
      fw_advance implementing "loop-driver: monitor cap $mcap 到達 — 人間介入が必要"
      echo "🛑 flywheel: 監視 council が $mcap 回試行しても verdict を記録できません。人間に返します（Skill: flywheel:monitor が機能しているか確認してください）。" >&2
      exit 0
    fi
    fw_log_usage "steer:monitor"
    wf="$(fw_get '.watch_focus')"
    echo "🔎 flywheel: eval 合格（$eval_cmd）。done の前に Skill: flywheel:monitor で drift を検証してください（観測者を fan-out: 要件逸脱 / 挙動 / 進捗）。${wf:+ 重点(watch-focus): $wf}" >&2
    exit 2
  elif [[ "$mstatus" == "pending" ]]; then
    if monitor_bump; then
      fw_set_json monitor null; fw_set_json monitor_attempts 0
      fw_advance implementing "loop-driver: monitor cap $mcap 到達 — 人間介入が必要"
      echo "🛑 flywheel: 監視 council が $mcap 回試行しても verdict を記録できません。人間に返します（Skill: flywheel:monitor が機能しているか確認してください）。" >&2
      exit 0
    fi
    echo "🔎 flywheel: 監視 council の verdict が未記録です。Skill: flywheel:monitor を実行し、終わりに 'flywheel monitor-set <clean|drift> [level] [reason]' で結果を記録してください。" >&2
    exit 2
  elif [[ "$mstatus" == "drift" ]]; then
    mlevel="$(fw_get '.monitor.level')"
    mreason="$(fw_get '.monitor.reason')"
    fw_set_json monitor null   # クリア（修正後の緑で再検証させる）
    case "$mlevel" in
      design|requirements)
        # 巻き戻し天井: design/PRD レベルは自動で戻さず人間に hand-back（phase=designing で停止）。
        fw_set_json monitor_attempts 0
        fw_advance designing "loop-driver: monitor drift ($mlevel) → 人間 hand-back"
        cat >&2 <<EOF
🛑 flywheel: 監視 council が ${mlevel} レベルの drift を検知しました。自動では戻せません（人間判断）。
理由: $mreason
→ 設計ゲートを再度開きました（phase=designing）。plan/design.md（必要なら plan/requirements.md）を見直してください。
EOF
        exit 0   # stop 許可（人間へ hand-back）
        ;;
      *)
        # implementing レベル（既定）: コードを直す。ただし同じ drift が cap 回続くなら設計レベルを疑い人間へ escalate。
        if monitor_bump; then
          fw_set_json monitor_attempts 0
          fw_advance designing "loop-driver: monitor drift(impl) が $mcap 回未解消 → 設計レベル疑い・人間 hand-back"
          cat >&2 <<EOF
🛑 flywheel: 監視 council が implementing レベルの drift を $mcap 回検出しましたが解消しません。設計レベルの問題の可能性が高いので人間に返します。
理由: $mreason
→ 設計ゲートを再度開きました（phase=designing）。plan/design.md を見直してください。
EOF
          exit 0
        fi
        fw_advance implementing "loop-driver: monitor drift (impl) → 差し戻し"
        cat >&2 <<EOF
🔁 flywheel: eval は緑ですが監視 council が drift を検知しました（done にできません）。修正して続けてください。
理由: $mreason
（この verdict は処理済み・クリア済みです。修正したら次の停止で自動的に再 monitor が走ります＝古い verdict を読み続けるわけではありません）
EOF
        exit 2
        ;;
    esac
  elif [[ "$mstatus" == "clean" ]]; then
    # monitor 通過 → done へ進む（FR-34）。挙動検証は独立な monitor council に統合済み:
    # observer-behavior レンズが「runnable なら runtime エビデンスがあるか」を判定し、薄い eval の
    # runnable goal で runtime 未検証なら drift(impl) として戻す。self-graded な検証ゲート
    # （旧 FR-32）は撤去した（done を閉めるのは eval(客観)+monitor(独立)の2つだけ）。
    fw_set_json monitor null; fw_set_json monitor_attempts 0
    fw_advance done "loop-driver: eval pass ($eval_cmd) + monitor clean"
  else
    # fail-closed: 未知の verdict（typo 等）は信用しない。クリアして再検証を強制し、done をすり抜けさせない。
    fw_set_json monitor null
    if monitor_bump; then
      fw_set_json monitor_attempts 0
      fw_advance implementing "loop-driver: monitor 不正 verdict が $mcap 回 — 人間介入が必要"
      echo "🛑 flywheel: monitor verdict が $mcap 回不正です（最新 status=$mstatus）。人間に返します。" >&2
      exit 0
    fi
    echo "🔎 flywheel: monitor verdict が不正（status=$mstatus）。Skill: flywheel:monitor で検証し直してください。" >&2
    exit 2
  fi
  arch="$(fw_archive_plan)"   # FR-12: 完了スペックを退避（plan/ をクリーンに）
  echo "✅ flywheel: eval 合格（$eval_cmd）。goal 達成として done。" >&2
  [[ -n "$arch" ]] && echo "   設計を退避: ${arch#"$FW_ROOT"/}" >&2
  # --- adopt chain (FR-33): done で backlog があれば次の goal を自動起動し連続消化する ---
  # 安全性: next が backlog 先頭を pop する＝backlog は単調減少（空で自然停止・無限ループ不可）。
  #   stuck な goal は各 goal の veto/monitor cap が人間へ hand-back するので暴走しない（専用 cap 不要）。
  # 経路別: adopt（合意済み）は止めず設計→実装へ連鎖。start（要件を一から掘る）も FR-35 以降は
  #   HOTL で連鎖するが、連鎖前に go/no-go を grill し discovery 中の判断だけ人間に pop する
  #   （調べる=自動 / 決める=人間 / 判定=monitor）。
  # FLYWHEEL_NO_CHAIN=1 で従来の hard-stop（pop せず人間に促すだけ）へ戻す。
  n="$(fw_backlog_count)"
  if [[ "$n" -gt 0 && "${FLYWHEEL_NO_CHAIN:-}" != "1" ]]; then
    fw_chain_checkpoint   # FR-46: 完了 goal を独立 change に確定してから N+1 起動（jj のみ・履歴粒度保持）
    if "$FW_CLI" next >/dev/null 2>&1; then
      new_goal="$(fw_get '.goal')"
      if [[ "$(fw_get '.entry')" == "adopt" ]]; then
        fw_log_usage "steer:chain"
        cat >&2 <<EOF
🔗 flywheel: done → adopt chain で次の goal を自動起動しました（backlog 残 $(fw_backlog_count) 件）。
goal: $new_goal
→ 会話 / .claude/journal.md 先頭 Next / notes の合意を plan/design.md に結晶化してください（「## 完了条件（eval）」も）。合格で実装ゲートが開き、eval→done→次へ連鎖します。
EOF
        exit 2   # 連続自律: 止めずに次の設計へ進ませる
      fi
      # start 経路（要件を一から掘る）: HOTL で連鎖する（FR-35）。loop-driver は Stop hook で
      # AskUserQuestion を呼べないので、exit 2 + steer で次ターンのモデルに go/no-go grill →
      # discovery → 判断だけ grill を実行させる（調べる=自動 / 決める=人間 / 判定=monitor）。
      fw_log_usage "steer:start-chain"
      cat >&2 <<EOF
🔗 flywheel: done → 次は start 経路 goal（要件を一から掘る）。HOTL で連鎖します（backlog 残 $(fw_backlog_count) 件）。
goal: $new_goal
→ まず人間に go/no-go を1問 grill-me:「この goal を今掘りますか?」。
  ・no-go → discovery せず停止。goal は loaded(designing) のまま。再開するか /flywheel:reset で破棄するか人間が決める。
  ・go    → discovery を回す（曖昧なら /flywheel:deep-interview → /flywheel:discovery-council）。
            plan/requirements.md と plan/design.md を draft し、design ゲート→実装→eval→done→連鎖。
⚠️ 掘る過程で出た【判断】（スコープ/トレードオフ/優先度/命名/案の選択）は self-answer せず必ず grill-me。
   self-answer してよいのは【事実】（コードを読めば分かること）だけ。迷ったら聞く側。
EOF
      exit 2   # HOTL: 止めず次の設計（go/no-go grill から）へ進ませる
    fi
    echo "⚠️ flywheel: 次 goal の自動起動に失敗しました。'$FW_CLI next' で手動起動してください（backlog 残 $n 件）。" >&2
    exit 0
  fi
  [[ "$n" -gt 0 ]] && echo "📋 flywheel: done。backlog に $n 件（FLYWHEEL_NO_CHAIN=1 のため自動連鎖せず）。'$FW_CLI next' で次へ。" >&2
  exit 0   # stop 許可（backlog 空 or 連鎖無効）
fi

# ここから eval 失敗（rc != 0）。緑が崩れたら監視 verdict と試行回数は破棄（次の緑で再検証・FR-30）。
# 赤領域の暴走は eval veto が cap で止める。監視カウンタは緑領域専用なのでリセットする。
fw_set_json monitor null
fw_set_json monitor_attempts 0

# 失敗 → veto。cap 到達なら人間に返す（FR-10）、未満なら implementing に戻して継続強制。
if bump_veto_or_handoff "eval が通りません（$eval_cmd）。最新の失敗:
$(printf '%s' "$out" | tail -15)"; then
  exit 0   # cap 到達 → stop 許可（人間判断へ）
fi

hint=""
[[ "$prev_phase" == "polish" ]] && hint=" 直前が polish なので simplify の変更が壊した可能性が高い — その差分を疑ってください。"

# FR-25: fail 数の進捗方向。悪化したら「失敗を積んだまま重ねない」= revert 規律を steer。
cur_fails="$(printf '%s' "$out" | fw_count_fails)"
prev_fails="$(fw_get '.last_fail_count')"
[[ -n "$cur_fails" ]] && fw_set_json last_fail_count "$cur_fails"
trend=""
if [[ -n "$cur_fails" && -n "$prev_fails" ]]; then
  if (( cur_fails < prev_fails )); then
    trend=" 📉 進捗: fail ${prev_fails}→${cur_fails}。方向は正しい——このアプローチで続行。"
  elif (( cur_fails > prev_fails )); then
    trend=" 📈 悪化: fail ${prev_fails}→${cur_fails}。**直前の変更を戻してから**別のアプローチを試してください（git revert / jj op restore / 該当編集の取り消し）。失敗した変更を積んだまま次を重ねないこと。"
  else
    trend=" ➡️ 横ばい: fail ${prev_fails} のまま。同じアプローチの微調整ではなく、別の仮説を検討してください。"
  fi
fi

# eval_cmd 自体が解決できていないシグナル（コマンド名ミス・未インストール・パス誤り）を検出したら、
# 「直すべきはコードでなく eval_cmd」と示唆する。最初の veto から出して長い迂回を短絡する。
# 通常のテスト失敗（assert 落ち）には下記パターンが出ないので誤検知しにくい。
cmd_hint=""
# シェル(bash -c 経由)が eval_cmd を解決できなかった signal だけに絞る＝行頭/パスの shell プレフィクス付き。
# 裸の "No such file or directory" / ": not found" は通常のテスト失敗出力（例: 'config.yml: No such
# file or directory'）にも現れるので誤検知する → プレフィクスで弾く。
if printf '%s' "$out" | grep -qE '(^|/)(bash|zsh|sh|dash|ash): .*(command not found|No such file or directory|: not found)'; then
  cmd_hint=" ⚠️ eval_cmd が解決できていない可能性（シェルが command not found）。コードでなく eval_cmd の指定ミスなら 'flywheel set-eval \"<正しいコマンド>\"' で直せます。"
fi

fw_advance implementing "loop-driver: eval fail, veto $veto/$cap"
cat >&2 <<EOF
🔁 flywheel: eval 未達（$eval_cmd, veto $veto/$cap）。done にできません。修正して続けてください。$hint$trend$cmd_hint
goal: $(fw_get '.goal')
失敗内容:
$(printf '%s' "$out" | tail -15)
EOF
exit 2   # stop を拒否 → 継続強制
