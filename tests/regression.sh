#!/usr/bin/env bash
#
# regression.sh —— ai-collaboration-guard 脚本的回归测试
#
# 在临时目录里建裸 remote + 多 clone/worktree 模拟，覆盖三个脚本的行为。
# 跑完打印 PASS/FAIL 计数；任一失败 exit 非零。
#
# 用法：bash tests/regression.sh
# 日志同时写到 tests/regression.log
#
set -u

HERE="$(cd "$(dirname "$0")/.." && pwd)"
SYNC="$HERE/scripts/safe_sync.sh"
PREFLIGHT="$HERE/scripts/preflight.sh"
REMOTE_CHECK="$HERE/scripts/remote_check.sh"
# 隔离 git 配置，不读宿主机的 global/system config
GLOBAL_DIR="$(mktemp -d)" || { echo "mktemp failed"; exit 1; }
export GIT_CONFIG_GLOBAL="$GLOBAL_DIR/empty.gitconfig"
export GIT_CONFIG_SYSTEM="/dev/null"
touch "$GIT_CONFIG_GLOBAL"

PASS=0
FAIL=0
pass() { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
expect_eq() {
  if [ "$2" = "$3" ]; then pass "$1"; else fail "$1 (expected='$2' got='$3')"; fi
}
expect_ne() {
  if [ "$2" != "$3" ]; then pass "$1"; else fail "$1 (got same='$2')"; fi
}
expect_contains() {
  if printf '%s' "$2" | grep -qF -- "$3"; then pass "$1"; else fail "$1 (no substring '$3')"; fi
}
hdr() { echo; echo "=== $1 ==="; }

ROOT="$(mktemp -d -t acg-regression.XXXXXX)" || { echo "mktemp failed"; exit 1; }
echo "测试根目录：$ROOT"
trap 'rm -rf "$ROOT" "$GLOBAL_DIR"' EXIT

# fake gh: 返回空 PR 数组（[]），用于让 remote_check 的 PR 部分走"无 open PR"分支
FAKEBIN="$ROOT/fakebin"; mkdir -p "$FAKEBIN"
cat > "$FAKEBIN/gh" <<'GH'
#!/bin/sh
case "$1" in auth) exit 0;; api) printf '[]\n'; exit 0;; esac
GH
chmod +x "$FAKEBIN/gh"
FAKE_PATH="$FAKEBIN:/usr/bin:/bin"


# 通用：在某目录里安静地做一个 commit
mkcommit() {
  (
    cd "$1" || exit 1
    printf '%s\n' "$3" > "$2"
    git add "$2"
    git commit -q -m "commit: $2" || exit 1
  )
}

# 每个用例开始前重置一个干净的 origin + 两个 clone
fresh_setup() {
  local name="$1"
  local dir="$ROOT/$name"
  mkdir -p "$dir" || { echo "setup failed: mkdir"; exit 1; }
  git init --bare -b main "$dir/origin.git" >/dev/null || { echo "setup failed: bare init"; exit 1; }
  git init -q -b main "$dir/seed" || { echo "setup failed: seed init"; exit 1; }
  ( cd "$dir/seed"
    git config user.name "Tester"
    git config user.email "tester@example.com"
    echo "# seed" > README.md
    git add README.md
    git commit -q -m "seed" || exit 1
    git remote add origin "$dir/origin.git" || exit 1
    git push -q origin main || exit 1
  ) || { echo "setup failed: seed push"; exit 1; }
  git clone -q "$dir/origin.git" "$dir/A" || { echo "setup failed: clone A"; exit 1; }
  git clone -q "$dir/origin.git" "$dir/B" || { echo "setup failed: clone B"; exit 1; }
  ( cd "$dir/A" && git config user.name "Alice" && git config user.email "alice@example.com" )
  ( cd "$dir/B" && git config user.name "Bob"   && git config user.email "bob@example.com" )
  # 把 origin URL 改成 GitHub 风格（让 remote_check 能解析 slug），同时用 insteadOf 重写回本地路径供 fetch
  for c in "$dir/A" "$dir/B"; do
    ( cd "$c"
      git remote set-url origin "git@github.com:test/test.git"
      git config "url.$dir/origin.git.insteadOf" "git@github.com:test/test.git"
    )
  done
}

############################################
# 1) tracking remote 不叫 origin、tracking 分支名与本地不同
############################################
hdr "1) tracking remote 不叫 origin、tracking 分支名与本地不同"
{
  fresh_setup "case1"
  d="$ROOT/case1"
  ( cd "$d/A"
    git remote rename origin central
    git switch -q -c dev central/main
  )
  mkcommit "$d/B" "from_b.txt" "from B"
  ( cd "$d/B" && git push -q origin main )

  out="$( cd "$d/A" && bash "$SYNC" 2>&1 )"
  rc=$?
  expect_eq "case1: exit 0" "0" "$rc"
  expect_contains "case1: 识别 central" "$out" "central/main"
  [ -f "$d/A/from_b.txt" ] && pass "case1: dev 已同步到 B 的提交" || fail "case1: dev 没拿到 B 的提交"
}

############################################
# 2) fork 场景：origin=fork, upstream=原仓库
############################################
hdr "2) fork 场景：origin=fork, upstream=原仓库"
{
  d="$ROOT/case2"
  mkdir -p "$d"
  git init --bare -b main "$d/upstream.git" >/dev/null
  git init --bare -b main "$d/myfork.git" >/dev/null
  git init -q -b main "$d/seed"
  ( cd "$d/seed"
    git config user.name "T" && git config user.email "t@e.com"
    echo "# seed" > README.md && git add README.md && git commit -q -m seed
    git remote add upstream "$d/upstream.git"
    git remote add myfork "$d/myfork.git"
    git push -q upstream main
    git push -q myfork main
  )
  git clone -q "$d/myfork.git" "$d/work"
  ( cd "$d/work"
    git config user.name "Bob" && git config user.email "bob@e.com"
    git remote add upstream "$d/upstream.git"
  )
  mkcommit "$d/seed" "upstream_change.txt" "from upstream"
  ( cd "$d/seed" && git push -q upstream main )

  out="$( cd "$d/work" && bash "$SYNC" 2>&1 )"
  rc=$?
  expect_eq "case2: exit 0（myfork 没动，无需同步）" "0" "$rc"
  if [ -f "$d/work/upstream_change.txt" ]; then
    fail "case2: safe_sync 错把 upstream 拉进来了"
  else
    pass "case2: safe_sync 没动 upstream，只认 origin"
  fi
  ( cd "$d/work"
    git fetch -q upstream
    git merge --ff-only upstream/main
  )
  [ -f "$d/work/upstream_change.txt" ] && pass "case2: 手工 ff-only 同步 upstream 成功" || fail "case2: 手工同步失败"
}

############################################
# 3) 无 upstream → 非零退出
############################################
hdr "3) 无 upstream → 非零退出"
{
  fresh_setup "case3"
  d="$ROOT/case3"
  ( cd "$d/A" && git switch -q -c no-upstream )
  out="$( cd "$d/A" && bash "$SYNC" 2>&1 )"
  rc=$?
  expect_ne "case3: 非零退出" "0" "$rc"
  expect_contains "case3: 提示 push -u" "$out" "push -u"
}

############################################
# 4) 未知参数 → 报错（含第二个未知参数）
############################################
hdr "4) 未知参数 → 报错"
{
  fresh_setup "case4"
  out="$( cd "$ROOT/case4/A" && bash "$SYNC" --bogus 2>&1 )"
  rc=$?
  expect_ne "case4a: 单未知参数非零" "0" "$rc"
  expect_contains "case4a: 提示未知参数" "$out" "未知参数"

  out="$( cd "$ROOT/case4/A" && bash "$SYNC" --dry-run --bogus 2>&1 )"
  rc=$?
  expect_ne "case4b: 第二参数也拒绝" "0" "$rc"
}

############################################
# 5) 脏工作区：三种改动都不被丢
############################################
hdr "5) 脏工作区：三种改动都不被丢"
{
  fresh_setup "case5"
  d="$ROOT/case5"
  ( cd "$d/A"
    echo "unstaged" >> README.md
    echo "staged-new" > staged.txt
    git add staged.txt
    echo "untracked-new" > untracked.txt
  )
  out="$( cd "$d/A" && bash "$SYNC" 2>&1 )"
  rc=$?
  expect_ne "case5: 脏工作区拒绝" "0" "$rc"
  expect_contains "case5: 提示先提交或 stash" "$out" "我不会替你丢"
  grep -q "unstaged" "$d/A/README.md" && pass "case5: 未暂存改动还在" || fail "case5: 未暂存改动丢了"
  grep -q "staged-new" "$d/A/staged.txt" && pass "case5: 已暂存文件还在" || fail "case5: 已暂存文件丢了"
  grep -q "untracked-new" "$d/A/untracked.txt" && pass "case5: 未跟踪文件还在" || fail "case5: 未跟踪文件丢了"
}

############################################
# 5b) 纯暂存（已 git add 未 commit）→ safe_sync 拒绝
############################################
hdr "5b) 纯暂存 → safe_sync 拒绝"
{
  fresh_setup "case5b"
  d="$ROOT/case5b"
  ( cd "$d/A"
    echo "staged-only" > staged.txt
    git add staged.txt
  )
  out="$( cd "$d/A" && bash "$SYNC" 2>&1 )"; rc=$?
  expect_ne "case5b: 纯暂存也应被拒绝" "0" "$rc"
  expect_contains "case5b: 提示先提交或 stash" "$out" "我不会替你丢"
  grep -q "staged-only" "$d/A/staged.txt" && pass "case5b: 暂存文件内容还在" || fail "case5b: 暂存文件被丢"
}

############################################
# 6) detached / unborn / rebase 中 / revert 中 → 停下
############################################
hdr "6) detached / unborn / rebase 中 / revert 中 → 停下"
{
  fresh_setup "case6"
  d="$ROOT/case6"

  ( cd "$d/A" && git switch -q --detach origin/main )
  out="$( cd "$d/A" && bash "$SYNC" 2>&1 )"; rc=$?
  expect_ne "case6a: detached 非零" "0" "$rc"
  expect_contains "case6a: 提示 detached" "$out" "detached"
  ( cd "$d/A" && git switch -q main )

  ( cd "$d/A" && git checkout -q --orphan empty-branch )
  out="$( cd "$d/A" && bash "$SYNC" 2>&1 )"; rc=$?
  expect_ne "case6b: unborn 非零" "0" "$rc"
  ( cd "$d/A" && git checkout -q main )

  mkdir -p "$d/A/.git/rebase-merge"
  out="$( cd "$d/A" && bash "$SYNC" 2>&1 )"; rc=$?
  expect_ne "case6c: rebase 中 非零" "0" "$rc"
  expect_contains "case6c: 提示 rebase 中途" "$out" "rebase"
  rmdir "$d/A/.git/rebase-merge"

  echo "revert-me" > "$d/A/.git/REVERT_HEAD"
  out="$( cd "$d/A" && bash "$SYNC" 2>&1 )"; rc=$?
  expect_ne "case6d: revert 中 非零" "0" "$rc"
  expect_contains "case6d: 提示 revert" "$out" "revert"
  rm "$d/A/.git/REVERT_HEAD"
}

############################################
# 7) 分叉 → 不替用户 rebase，给出可执行的 merge 建议
############################################
hdr "7) 分叉 → 不替用户 rebase"
{
  fresh_setup "case7"
  d="$ROOT/case7"
  mkcommit "$d/B" "b_first.txt" "b first"
  ( cd "$d/B" && git push -q origin main )
  mkcommit "$d/A" "a_first.txt" "a first"
  a_sha_before="$( cd "$d/A" && git rev-parse HEAD )"
  push_out="$( cd "$d/A" && git push origin main 2>&1 )"; push_rc=$?
  expect_ne "case7: A 直接 push 被拒" "0" "$push_rc"
  out="$( cd "$d/A" && bash "$SYNC" 2>&1 )"; rc=$?
  expect_ne "case7: 分叉时非零退出" "0" "$rc"
  expect_contains "case7: 提示分叉" "$out" "分叉"
  expect_contains "case7: 给出可执行的 merge 命令" "$out" "git merge --no-edit"
  # 真的执行这条建议，验证可执行且保留双方历史
  ( cd "$d/A" && git merge origin/main --no-edit -m "merge test" 2>/dev/null || true )
  if ( cd "$d/A" && git merge-base --is-ancestor "$a_sha_before" HEAD 2>/dev/null ); then
    pass "case7: A 的原 commit 在 merge 后仍在历史里"
  else
    fail "case7: A 的原 commit 丢了"
  fi
}

############################################
# 8) --dry-run 不真 fetch
############################################
hdr "8) --dry-run 不真 fetch"
{
  fresh_setup "case8"
  d="$ROOT/case8"
  mkcommit "$d/B" "b_dry.txt" "b dry"
  ( cd "$d/B" && git push -q origin main )
  old_sha="$( cd "$d/A" && git rev-parse origin/main )"
  ( cd "$d/A" && bash "$SYNC" --dry-run >/dev/null 2>&1 )
  new_sha="$( cd "$d/A" && git rev-parse origin/main )"
  expect_eq "case8: dry-run 后 origin/main 未变" "$old_sha" "$new_sha"
}

############################################
# 9) ref 读取失败 → 非零、不假成功
############################################
hdr "9) ref 读取失败 → 非零"
{
  fresh_setup "case9"
  d="$ROOT/case9"
  ( cd "$d/A"
    git config branch.main.remote origin
    git config branch.main.merge refs/heads/does-not-exist
  )
  out="$( cd "$d/A" && bash "$SYNC" 2>&1 )"; rc=$?
  expect_ne "case9: 非零退出" "0" "$rc"
  if printf '%s' "$out" | grep -qF "同步完成"; then fail "case9: 假报同步完成"; else pass "case9: 没假报成功"; fi
}

############################################
# 10) 标准 ff-only 同步成功
############################################
hdr "10) 标准 ff-only 同步成功"
{
  fresh_setup "case10"
  d="$ROOT/case10"
  mkcommit "$d/B" "b_sync.txt" "b sync"
  ( cd "$d/B" && git push -q origin main )
  out="$( cd "$d/A" && bash "$SYNC" 2>&1 )"; rc=$?
  expect_eq "case10: exit 0" "0" "$rc"
  expect_contains "case10: ff-only" "$out" "ff-only"
  [ -f "$d/A/b_sync.txt" ] && pass "case10: A 拿到 B 的提交" || fail "case10: A 没拿到"
}

############################################
# 11) 两个 feature 分支依次合入主线，再同步到另一 clone
############################################
hdr "11) 两个 feature 合入 main，再同步到新 clone"
{
  fresh_setup "case11"
  d="$ROOT/case11"
  ( cd "$d/A"
    git switch -q -c feature/x
    echo "x" > x.txt && git add x.txt && git commit -q -m "x"
    git push -q -u origin feature/x
    git switch -q main
    git merge -q --no-ff feature/x -m "merge feature/x"
    git push -q origin main
    git switch -q -c feature/y
    echo "y" > y.txt && git add y.txt && git commit -q -m "y"
    git push -q -u origin feature/y
    git switch -q main
    git merge -q --no-ff feature/y -m "merge feature/y"
    git push -q origin main
  )
  git clone -q "$d/origin.git" "$d/C"
  ( cd "$d/C" && git config user.name "C" && git config user.email "c@e.com" )
  out="$( cd "$d/C" && bash "$SYNC" 2>&1 )"; rc=$?
  expect_eq "case11: C 同步 exit 0" "0" "$rc"
  [ -f "$d/C/x.txt" ] && [ -f "$d/C/y.txt" ] && pass "case11: C 同时拿到 x 和 y" || fail "case11: C 没拿全"
}

############################################
# 12) git worktree 隔离
############################################
hdr "12) worktree 隔离：主 worktree 的未提交改动不影响新 worktree"
{
  fresh_setup "case12"
  d="$ROOT/case12"
  ( cd "$d/A"
    echo "uncommitted in main worktree" >> README.md
    git worktree add -q "$d/A-wt1" -b feature/wt1
  )
  if grep -q "uncommitted in main worktree" "$d/A-wt1/README.md"; then
    fail "case12: worktree 泄漏了主 worktree 的未提交改动"
  else
    pass "case12: worktree 不受主 worktree 未提交改动影响"
  fi
  wt_branch="$( cd "$d/A-wt1" && git symbolic-ref --short HEAD )"
  expect_eq "case12: worktree 在自己分支上" "feature/wt1" "$wt_branch"
}

# remote_check.sh 路径
REMOTE_CHECK="$HERE/scripts/remote_check.sh"

############################################
# 13) 两边从同一基线各自开发、先后 push
############################################
hdr "13) 两边从同一基线各自开发、先后 push"
{
  fresh_setup "case13"
  d="$ROOT/case13"
  mkcommit "$d/A" "a_file.txt" "A's work"
  mkcommit "$d/B" "b_file.txt" "B's work"
  ( cd "$d/A" && git push -q origin main )
  push_out="$( cd "$d/B" && git push origin main 2>&1 )"; push_rc=$?
  expect_ne "case13: B 先推被拒（A 已推）" "0" "$push_rc"
  out="$( cd "$d/B" && bash "$SYNC" 2>&1 )"; rc=$?
  expect_ne "case13: B 分叉时 safe_sync 停下" "0" "$rc"
  expect_contains "case13: 提示分叉" "$out" "分叉"
  ( cd "$d/B" && git merge origin/main --no-edit -m "merge origin/main" )
  ( cd "$d/B" && git push -q origin main )
  ( cd "$d/A" && git fetch -q origin && git merge origin/main --no-edit -m "merge origin/main" )
  [ -f "$d/A/b_file.txt" ] && [ -f "$d/A/a_file.txt" ] && pass "case13: A 同步后拿到 B 的活" || fail "case13: A 没拿全"
}

############################################
# 14) remote_check：feature 分支 tracking 不变，但 main 变了
############################################
hdr "14) remote_check 报 main 落后"
{
  fresh_setup "case14"
  d="$ROOT/case14"
  ( cd "$d/A"
    git switch -q -c feature/thing
    echo "thing" > thing.txt && git add thing.txt && git commit -q -m "thing"
    git push -q -u origin feature/thing
  )
  mkcommit "$d/B" "b_new.txt" "b new on main"
  ( cd "$d/B" && git push -q origin main )
  out="$( cd "$d/A" && env PATH="$FAKE_PATH" bash "$REMOTE_CHECK" 2>&1 )"; rc=$?
  expect_eq "case14: 有新提交时 exit 1 (ATTENTION)" "1" "$rc"
  expect_contains "case14: 报告 CHANGED: yes" "$out" "CHANGED: yes"
  expect_contains "case14: STATUS: ATTENTION" "$out" "STATUS: ATTENTION"
}

############################################
# 15) 两个 feature 分别能合进 main，但彼此冲突（用 python 改同一行，可移植）
############################################
hdr "15) 两个 feature 分别能合 main，但彼此冲突"
{
  fresh_setup "case15"
  d="$ROOT/case15"
  ( cd "$d/A"
    git switch -q -c feature/a
    python3 -c "p='README.md'; s=open(p).read(); open(p,'w').write(s.replace('# seed','# seed by A'))"
    git add README.md && git commit -q -m "a edits README"
    git push -q -u origin feature/a
  )
  ( cd "$d/B"
    git switch -q -c feature/b
    python3 -c "p='README.md'; s=open(p).read(); open(p,'w').write(s.replace('# seed','# seed by B'))"
    git add README.md && git commit -q -m "b edits README"
    git push -q -u origin feature/b
  )
  ( cd "$d/A"
    git switch -q main
    git merge -q --no-ff feature/a -m "merge feature/a"
    git push -q origin main
  )
  merge_out="$( cd "$d/B"
    git switch -q main
    git fetch -q origin
    git merge -q origin/main --no-edit -m "sync main"
    git merge --no-ff feature/b -m "merge feature/b" 2>&1
  )"; merge_rc=$?
  expect_ne "case15: 合 feature/b 进 main 冲突" "0" "$merge_rc"
  expect_contains "case15: 有冲突标记" "$merge_out" "CONFLICT"
  ( cd "$d/B" && git merge --abort )
}

############################################
# 16) 检查完后 base/head 又变了 → 识别过期
############################################
hdr "16) 检查完后 base/head 变了 → 识别过期"
{
  fresh_setup "case16"
  d="$ROOT/case16"
  out1="$( cd "$d/A" && env PATH="$FAKE_PATH" bash "$REMOTE_CHECK" 2>&1 )"
  expect_contains "case16: 第一次 STATUS: OK" "$out1" "STATUS: OK"
  mkcommit "$d/B" "late.txt" "late push"
  ( cd "$d/B" && git push -q origin main )
  cached="$( cd "$d/A" && git rev-list --left-right --count origin/main...main 2>/dev/null || echo '0 0' )"
  cached_behind="$(echo "$cached" | awk '{print $1}')"
  expect_eq "case16: 未重新 fetch 时缓存显示落后 0（旧数据）" "0" "$cached_behind"
  out2="$( cd "$d/A" && env PATH="$FAKE_PATH" bash "$REMOTE_CHECK" 2>&1 )"
  expect_contains "case16: 重查后 CHANGED: yes" "$out2" "CHANGED: yes"
}

############################################
# 17) remote_check fetch 失败 → UNKNOWN 非零
############################################
hdr "17) remote_check fetch 失败 → UNKNOWN"
{
  fresh_setup "case17"
  d="$ROOT/case17"
  ( cd "$d/A" && git remote set-url origin "https://127.0.0.1:1/nope.git" )
  out="$( cd "$d/A" && bash "$REMOTE_CHECK" 2>&1 )"; rc=$?
  expect_ne "case17: 非零退出" "0" "$rc"
  expect_contains "case17: 输出 UNKNOWN" "$out" "STATUS: UNKNOWN"
}

############################################
# 18) remote_check 不在 git 仓库 → 报错
############################################
hdr "18) remote_check 不在 git 仓库 → 报错"
{
  out="$( cd /tmp && bash "$REMOTE_CHECK" 2>&1 )"; rc=$?
  expect_ne "case18: 非零退出" "0" "$rc"
  expect_contains "case18: 提示不在仓库" "$out" "不在 Git 工作区"
}

############################################
# 19) remote_check 无 gh 时 PR_STATUS: unknown（干净仓库仍 exit 0）
############################################
hdr "19) remote_check 无 gh => UNKNOWN 非零，不能 OK"
{
  fresh_setup "case19"
  d="$ROOT/case19"
  out="$( cd "$d/A" && env PATH=/usr/bin:/bin bash "$REMOTE_CHECK" --base origin/main 2>&1 )"; rc=$?
  expect_eq "case19: 无 gh 必须 exit 2" "2" "$rc"
  expect_contains "case19: STATUS UNKNOWN" "$out" "STATUS: UNKNOWN"
  if printf '%s' "$out" | grep -q "STATUS: OK"; then fail "case19: 不应出现 STATUS: OK"; else pass "case19: 无 STATUS: OK"; fi
}

############################################
# 20) remote_check 显式 --base
############################################
hdr "20) remote_check 显式 --base + fake gh 返回空 PR 数组 => none"
{
  fresh_setup "case20"
  d="$ROOT/case20"
  fake="$d/bin"; mkdir -p "$fake"
  cat > "$fake/gh" <<'GH'
#!/bin/sh
case "$1" in auth) exit 0;; api) printf '[]\n'; exit 0;; esac
GH
  chmod +x "$fake/gh"
  out="$( cd "$d/A" && env PATH="$fake:/usr/bin:/bin" bash "$REMOTE_CHECK" --base origin/main 2>&1 )"; rc=$?
  expect_eq "case20: 空 PR 数组 exit 0" "0" "$rc"
  expect_contains "case20: 打印 BASE" "$out" "BASE: origin/main"
  expect_contains "case20: PR_STATUS none" "$out" "PR_STATUS: none"
}

############################################
# 21) safe_sync 拒绝第二个参数
############################################
hdr "21) safe_sync 多参数拒绝"
{
  fresh_setup "case21"
  out="$( cd "$ROOT/case21/A" && bash "$SYNC" --dry-run extra 2>&1 )"; rc=$?
  expect_ne "case21: 多参数非零" "0" "$rc"
  expect_contains "case21: 提示参数太多" "$out" "参数太多"
}

############################################
# 22) remote_check fake gh 返回 malformed JSON => UNKNOWN
############################################
hdr "22) remote_check PR JSON malformed => UNKNOWN"
{
  fresh_setup "case22"
  d="$ROOT/case22"
  fake="$d/bin"; mkdir -p "$fake"
  cat > "$fake/gh" <<'GH'
#!/bin/sh
case "$1" in auth) exit 0;; api) printf 'not-json{{{{'; exit 0;; esac
GH
  chmod +x "$fake/gh"
  out="$( cd "$d/A" && env PATH="$fake:/usr/bin:/bin" bash "$REMOTE_CHECK" --base origin/main 2>&1 )"; rc=$?
  expect_eq "case22: malformed PR exit 2" "2" "$rc"
  expect_contains "case22: STATUS UNKNOWN" "$out" "STATUS: UNKNOWN"
}

############################################
# 23) remote_check fake gh 返回两个 open PR，嵌套 sha 都要读对
############################################
hdr "23) remote_check 列全部 open PR 且读对嵌套 sha"
{
  fresh_setup "case23"
  d="$ROOT/case23"
  fake="$d/bin"; mkdir -p "$fake"
  # 两个 PR：base.sha 与 head.sha 故意不同，验证 python 解析没把 base.sha 当 head.sha
  cat > "$fake/gh" <<'GH'
#!/bin/sh
case "$1" in
  auth) exit 0;;
  api) printf '[{"number":10,"base":{"ref":"main","sha":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"},"head":{"ref":"alice/f1","sha":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}},{"number":11,"base":{"ref":"main","sha":"cccccccccccccccccccccccccccccccccccccccc"},"head":{"ref":"bob/f2","sha":"dddddddddddddddddddddddddddddddddddddddd"}}]\n'; exit 0;;
esac
GH
  chmod +x "$fake/gh"
  out="$( cd "$d/A" && env PATH="$fake:/usr/bin:/bin" bash "$REMOTE_CHECK" --base origin/main 2>&1 )"; rc=$?
  # 有 open PR 需要 AI 核对 => ATTENTION（exit 1），不是 OK
  expect_eq "case23: 有 open PR => ATTENTION exit 1" "1" "$rc"
  expect_contains "case23: 读到 PR#10" "$out" "PR#10"
  expect_contains "case23: 读到 PR#11" "$out" "PR#11"
  expect_contains "case23: base.sha aaaa" "$out" "aaaaaaaa"
  expect_contains "case23: head.sha bbbb" "$out" "bbbbbbbb"
  expect_contains "case23: 第二个 base cccc" "$out" "cccccccc"
  expect_contains "case23: 第二个 head dddd" "$out" "dddddddd"
}

############################################
# 24) conflict_check 干净合并不需冲突
############################################
hdr "24) conflict_check: 只加新文件 => CLEAN"
{
  fresh_setup "case24"
  d="$ROOT/case24"
  ( cd "$d/A" && git switch -q -c feat && echo new > g.txt && git add g.txt && git commit -qm feat )
  out="$( cd "$d/A" && bash "$HERE/scripts/conflict_check.sh" origin/main feat 2>&1 )"; rc=$?
  expect_eq "case24: 干净合 exit 0" "0" "$rc"
  expect_contains "case24: CLEAN" "$out" "RESULT: CLEAN"
}

############################################
# 25) conflict_check 同一行双方都改 => CONFLICT
############################################
hdr "25) conflict_check: 同改一行 => CONFLICT"
{
  fresh_setup "case25"
  d="$ROOT/case25"
  ( cd "$d/A"
    git switch -q -c fa
    echo line-fa > x.txt && git add x.txt && git commit -qm fa
    git push -q origin fa
    git switch -q main
  )
  ( cd "$d/B"
    git switch -q -c fb
    echo line-fb > x.txt && git add x.txt && git commit -qm fb
  )
  # fa 和 fb 都从 main 加了不同内容的 x.txt（add/add 冲突）
  ( cd "$d/B" && git fetch -q origin )
  out="$( cd "$d/B" && bash "$HERE/scripts/conflict_check.sh" origin/fa fb 2>&1 )"; rc=$?
  expect_eq "case25: 冲突 exit 1" "1" "$rc"
  expect_contains "case25: CONFLICT" "$out" "RESULT: CONFLICT"
}

############################################
# 26) conflict_check 坏 ref => UNKNOWN exit 2
############################################
hdr "26) conflict_check: 坏 ref => UNKNOWN"
{
  fresh_setup "case26"
  d="$ROOT/case26"
  out="$( cd "$d/A" && bash "$HERE/scripts/conflict_check.sh" origin/main no-such-branch 2>&1 )"; rc=$?
  expect_eq "case26: 坏 ref exit 2" "2" "$rc"
}

############################################
# 27) gh 返回空数组但 exit 9（分页中途失败）=> UNKNOWN，不能当 none
############################################
hdr "27) gh exit 9 + 空数组 => UNKNOWN"
{
  fresh_setup "case27"
  d="$ROOT/case27"
  fake="$d/bin"; mkdir -p "$fake"
  cat > "$fake/gh" <<'GH'
#!/bin/sh
case "$1" in auth) exit 0;; api) printf '[]\n'; exit 9;; esac
GH
  chmod +x "$fake/gh"
  out="$( cd "$d/A" && env PATH="$fake:/usr/bin:/bin" bash "$REMOTE_CHECK" --base origin/main 2>&1 )"; rc=$?
  expect_eq "case27: exit 2" "2" "$rc"
  expect_contains "case27: UNKNOWN" "$out" "STATUS: UNKNOWN"
}

############################################
# 28) 第一个 PR 合法、第二个畸形 => 整体 MALFORMED
############################################
hdr "28) 有效+畸形 PR => UNKNOWN"
{
  fresh_setup "case28"
  d="$ROOT/case28"
  fake="$d/bin"; mkdir -p "$fake"
  B40=$(python3 -c "print('a'*40)")
  cat > "$fake/gh" <<GH
#!/bin/sh
case \$1 in
  auth) exit 0;;
  api) printf '[{"number":1,"base":{"ref":"main","sha":"$B40"},"head":{"ref":"x/y","sha":"$B40"}},{"broken":true}]\n'; exit 0;;
esac
GH
  chmod +x "$fake/gh"
  out="$( cd "$d/A" && env PATH="$fake:/usr/bin:/bin" bash "$REMOTE_CHECK" --base origin/main 2>&1 )"; rc=$?
  expect_eq "case28: exit 2" "2" "$rc"
  expect_contains "case28: UNKNOWN" "$out" "STATUS: UNKNOWN"
}

############################################
# 29) 多页：两个连续 JSON 数组都要被读出
############################################
hdr "29) 多页两个数组都读出"
{
  fresh_setup "case29"
  d="$ROOT/case29"
  fake="$d/bin"; mkdir -p "$fake"
  A40=$(python3 -c "print('a'*40)")
  B40=$(python3 -c "print('b'*40)")
  C40=$(python3 -c "print('c'*40)")
  D40=$(python3 -c "print('d'*40)")
  cat > "$fake/gh" <<GH
#!/bin/sh
case \$1 in
  auth) exit 0;;
  api) printf '[{"number":1,"base":{"ref":"main","sha":"$A40"},"head":{"ref":"p1","sha":"$B40"}}][{"number":2,"base":{"ref":"main","sha":"$C40"},"head":{"ref":"p2","sha":"$D40"}}]\n'; exit 0;;
esac
GH
  chmod +x "$fake/gh"
  out="$( cd "$d/A" && env PATH="$fake:/usr/bin:/bin" bash "$REMOTE_CHECK" --base origin/main 2>&1 )"; rc=$?
  expect_eq "case29: 两个 PR => ATTENTION exit 1" "1" "$rc"
  expect_contains "case29: PR#1" "$out" "PR#1"
  expect_contains "case29: PR#2" "$out" "PR#2"
}

############################################
# 30) conflict_check: 全局 custom merge driver 不被执行（sentinel 不产生）
############################################
hdr "30) conflict_check 不执行全局 merge driver"
{
  fresh_setup "case30"
  d="$ROOT/case30"
  sentinel="$GLOBAL_DIR/driver-sentinel"
  rm -f "$sentinel"
  # 配一个全局 merge driver，每次运行就 touch sentinel
  git config --global merge.baddriver.driver "touch $sentinel" 2>/dev/null || true
  git config --global merge.conflictStyle merge 2>/dev/null || true
  ( cd "$d/A" && git switch -q -c feat && echo new > g.txt && git add g.txt && git commit -qm feat )
  ( cd "$d/A" && bash "$HERE/scripts/conflict_check.sh" origin/main feat >/dev/null 2>&1 )
  if [ -f "$sentinel" ]; then
    fail "case30: 全局 merge driver 被执行了"
  else
    pass "case30: 全局 merge driver 未被执行"
  fi
  # 清理全局配置，避免污染其他用例
  git config --global --unset merge.baddriver.driver 2>/dev/null || true
}

############################################
# 31) conflict_check 跑完后源仓库 HEAD/index 不变
############################################
hdr "31) conflict_check 源仓库 HEAD/index 不变"
{
  fresh_setup "case31"
  d="$ROOT/case31"
  ( cd "$d/A" && git switch -q -c feat && echo new > g.txt && git add g.txt && git commit -qm feat )
  head_before="$( cd "$d/A" && git rev-parse HEAD )"
  idx_before="$( cd "$d/A" && git ls-files -s | git hash-object --stdin )"
  ( cd "$d/A" && bash "$HERE/scripts/conflict_check.sh" origin/main feat >/dev/null 2>&1 )
  head_after="$( cd "$d/A" && git rev-parse HEAD )"
  idx_after="$( cd "$d/A" && git ls-files -s | git hash-object --stdin )"
  [ "$head_before" = "$head_after" ] && pass "case31: HEAD 不变" || fail "case31: HEAD 变了"
  [ "$idx_before" = "$idx_after" ] && pass "case31: index 不变" || fail "case31: index 变了"
}

############################################
# 注释：语义审查不测
#
# "语义审查不能用测试代替"这一条是情景评估，不是脚本能测的行为。
# 上面 1-21 只测机械行为（fetch、ahead/behind、ff-only、脏工作区拒绝、worktree 隔离等）。
# "merge 干净 ≠ 逻辑对"、"测试绿 ≠ 没 bug"、"要 AI 自己读 diff 写依据"
# 这些由宿主 AI 按 references/ai-review-flow.md 负责，脚本证明不了。
# README 里也明说了这一点。
############################################

############################################
# 汇总
############################################
echo
echo "=========================================="
echo "PASS=$PASS  FAIL=$FAIL"
echo "=========================================="
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
