#!/usr/bin/env bash
#
# regression.sh —— ai-collaboration-guard 脚本的回归测试
#
# 在临时目录里建裸 remote + 多 clone/worktree 模拟，覆盖 safe_sync.sh 的 12 条行为。
# 跑完打印 PASS/FAIL 计数；任一失败 exit 非零。
#
# 用法：bash tests/regression.sh
#
set -u

HERE="$(cd "$(dirname "$0")/.." && pwd)"
SYNC="$HERE/scripts/safe_sync.sh"
PREFLIGHT="$HERE/scripts/preflight.sh"

PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
# expect_eq "描述" 期望 实际
expect_eq() {
  if [ "$2" = "$3" ]; then pass "$1"; else fail "$1 (expected='$2' got='$3')"; fi
}
# expect_ne "描述" 值1 值2
expect_ne() {
  if [ "$2" != "$3" ]; then pass "$1"; else fail "$1 (got same='$2')"; fi
}
# expect_contains "描述"  haystack needle
expect_contains() {
  if printf '%s' "$2" | grep -qF -- "$3"; then pass "$1"; else fail "$1 (no substring '$3')"; fi
}

# 每个用例前打印标题
hdr() { echo; echo "=== $1 ==="; }

# 全局：测试根目录
ROOT="$(mktemp -d -t acg-regression.XXXXXX)"
echo "测试根目录：$ROOT"
trap 'rm -rf "$ROOT"' EXIT

# 通用：在某目录里安静地做一个 commit
mkcommit() {
  # 用法: mkcommit <dir> <file> <content>
  (
    cd "$1" || exit 1
    printf '%s\n' "$3" > "$2"
    git add "$2"
    git commit -q -m "commit: $2"
  )
}

# 每个用例开始前重置一个干净的 origin + 两个 clone
fresh_setup() {
  # 用法: fresh_setup <name>
  local name="$1"
  local dir="$ROOT/$name"
  mkdir -p "$dir"
  git init --bare -b main "$dir/origin.git" >/dev/null
  # seed commit：显式 init -b main + 加 remote + push，避免 clone 空仓库时本地分支名不确定
  git init -q -b main "$dir/seed"
  ( cd "$dir/seed"
    git config user.name "Tester"
    git config user.email "tester@example.com"
    echo "# seed" > README.md
    git add README.md
    git commit -q -m "seed"
    git remote add origin "$dir/origin.git"
    git push -q origin main
  )
  # clone A and B
  git clone -q "$dir/origin.git" "$dir/A"
  git clone -q "$dir/origin.git" "$dir/B"
  ( cd "$dir/A" && git config user.name "Alice" && git config user.email "alice@example.com" )
  ( cd "$dir/B" && git config user.name "Bob"   && git config user.email "bob@example.com" )
}

############################################
# 1) tracking remote 不叫 origin、tracking 分支名与本地不同
############################################
hdr "1) tracking remote 不叫 origin、tracking 分支名与本地不同"
{
  fresh_setup "case1"
  d="$ROOT/case1"
  # A 把 origin 改名为 central，本地建一个 dev 分支跟踪 central/main
  ( cd "$d/A"
    git remote rename origin central
    git switch -q -c dev central/main
  )
  # B 在 main 上推一个新提交
  mkcommit "$d/B" "from_b.txt" "from B"
  ( cd "$d/B" && git push -q origin main )

  # A 在 dev 上跑 safe_sync，应识别 tracking remote=central
  out="$( cd "$d/A" && bash "$SYNC" 2>&1 )"
  rc=$?
  expect_eq "case1: exit 0" "0" "$rc"
  expect_contains "case1: 识别 central" "$out" "central/main"
  # A 的 dev 应该已经快进到包含 from_b.txt
  if [ -f "$d/A/from_b.txt" ]; then pass "case1: dev 已同步到 B 的提交"; else fail "case1: dev 没拿到 B 的提交"; fi
}

############################################
# 2) fork 场景：origin=自己的 fork，upstream=原仓库
############################################
hdr "2) fork 场景：origin=fork, upstream=原仓库"
{
  d="$ROOT/case2"
  mkdir -p "$d"
  git init --bare -b main "$d/upstream.git" >/dev/null
  git init --bare -b main "$d/myfork.git" >/dev/null
  # seed upstream：显式 init -b main + 加 remote + push
  git init -q -b main "$d/seed"
  ( cd "$d/seed"
    git config user.name "Tester" && git config user.email "t@e.com"
    echo "# seed" > README.md && git add README.md && git commit -q -m seed
    git remote add upstream "$d/upstream.git"
    git remote add myfork "$d/myfork.git"
    git push -q upstream main
    git push -q myfork main
  )
  # 本地从 myfork clone
  git clone -q "$d/myfork.git" "$d/work"
  ( cd "$d/work"
    git config user.name "Bob" && git config user.email "bob@e.com"
    git remote add upstream "$d/upstream.git"
  )
  # 原仓库 upstream 有新提交，但 myfork 没有
  mkcommit "$d/seed" "upstream_change.txt" "from upstream"
  ( cd "$d/seed" && git push -q upstream main )

  # 在 work 上跑 safe_sync：它应该同步 origin（=myfork），不是 upstream
  out="$( cd "$d/work" && bash "$SYNC" 2>&1 )"
  rc=$?
  expect_eq "case2: exit 0（myfork 没动，无需同步）" "0" "$rc"
  if [ -f "$d/work/upstream_change.txt" ]; then
    fail "case2: safe_sync 错把 upstream 拉进来了"
  else
    pass "case2: safe_sync 没动 upstream，只认 origin"
  fi
  # 手工按文档 fork 三步同步后，upstream 的改动才应该进来
  ( cd "$d/work"
    git fetch -q upstream
    git merge --ff-only upstream/main
  )
  if [ -f "$d/work/upstream_change.txt" ]; then pass "case2: 手工 ff-only 同步 upstream 成功"; else fail "case2: 手工同步失败"; fi
}

############################################
# 3) 当前分支无上游 → 非零、不假报成功
############################################
hdr "3) 无 upstream → 非零退出"
{
  fresh_setup "case3"
  d="$ROOT/case3"
  ( cd "$d/A"
    git switch -q -c no-upstream
  )
  out="$( cd "$d/A" && bash "$SYNC" 2>&1 )"
  rc=$?
  expect_ne "case3: 非零退出" "0" "$rc"
  expect_contains "case3: 提示 push -u" "$out" "push -u"
}

############################################
# 4) 未知参数 → 报错
############################################
hdr "4) 未知参数 → 报错"
{
  fresh_setup "case4"
  out="$( cd "$ROOT/case4/A" && bash "$SYNC" --bogus 2>&1 )"
  rc=$?
  expect_ne "case4: 非零退出" "0" "$rc"
  expect_contains "case4: 提示未知参数" "$out" "未知参数"
}

############################################
# 5) 已暂存/未暂存/未跟踪三种改动被保留
############################################
hdr "5) 脏工作区：三种改动都不被丢"
{
  fresh_setup "case5"
  d="$ROOT/case5"
  ( cd "$d/A"
    # 未暂存改动
    echo "unstaged" >> README.md
    # 已暂存改动
    echo "staged-new" > staged.txt
    git add staged.txt
    # 未跟踪新文件
    echo "untracked-new" > untracked.txt
  )
  out="$( cd "$d/A" && bash "$SYNC" 2>&1 )"
  rc=$?
  expect_ne "case5: 脏工作区拒绝" "0" "$rc"
  expect_contains "case5: 提示先提交或 stash" "$out" "我不会替你丢"
  # 断言三种内容都还在
  grep -q "unstaged" "$d/A/README.md" && pass "case5: 未暂存改动还在" || fail "case5: 未暂存改动丢了"
  grep -q "staged-new" "$d/A/staged.txt" && pass "case5: 已暂存文件还在" || fail "case5: 已暂存文件丢了"
  grep -q "untracked-new" "$d/A/untracked.txt" && pass "case5: 未跟踪文件还在" || fail "case5: 未跟踪文件丢了"
}

############################################
# 5b) 只暂存、无未暂存/未跟踪 → 也要被当成脏工作区拦下
############################################
hdr "5b) 纯暂存（已 git add 未 commit）→ safe_sync 拒绝"
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
# 6) detached / unborn / 正在 rebase 中 → 停下
############################################
hdr "6) detached / unborn / rebase 中 → 停下"
{
  fresh_setup "case6"
  d="$ROOT/case6"

  # 6a detached HEAD
  ( cd "$d/A" && git switch -q --detach origin/main )
  out="$( cd "$d/A" && bash "$SYNC" 2>&1 )"; rc=$?
  expect_ne "case6a: detached 非零" "0" "$rc"
  expect_contains "case6a: 提示 detached" "$out" "detached"
  ( cd "$d/A" && git switch -q main )

  # 6b unborn HEAD
  ( cd "$d/A" && git checkout -q --orphan empty-branch )
  out="$( cd "$d/A" && bash "$SYNC" 2>&1 )"; rc=$?
  expect_ne "case6b: unborn 非零" "0" "$rc"
  ( cd "$d/A" && git checkout -q main )

  # 6c 正在 rebase（伪造 rebase-merge 目录）
  mkdir -p "$d/A/.git/rebase-merge"
  out="$( cd "$d/A" && bash "$SYNC" 2>&1 )"; rc=$?
  expect_ne "case6c: rebase 中 非零" "0" "$rc"
  expect_contains "case6c: 提示 rebase 中途" "$out" "rebase"
  rmdir "$d/A/.git/rebase-merge"
}

############################################
# 7) 分叉（ahead+behind）→ 默认不 rebase、停下
############################################
hdr "7) 分叉 → 不替用户 rebase"
{
  fresh_setup "case7"
  d="$ROOT/case7"
  # B 先在 main 上推一个提交
  mkcommit "$d/B" "b_first.txt" "b first"
  ( cd "$d/B" && git push -q origin main )
  # A 在 main 上做一个本地提交（A 还不知道 B 的提交）
  mkcommit "$d/A" "a_first.txt" "a first"
  a_sha_before="$( cd "$d/A" && git rev-parse HEAD )"
  # A 直接 push 会被拒
  push_out="$( cd "$d/A" && git push origin main 2>&1 )"; push_rc=$?
  expect_ne "case7: A 直接 push 被拒" "0" "$push_rc"
  # A 跑 safe_sync：应识别分叉、停下、不 rebase
  out="$( cd "$d/A" && bash "$SYNC" 2>&1 )"; rc=$?
  expect_ne "case7: 分叉时非零退出" "0" "$rc"
  expect_contains "case7: 提示分叉" "$out" "分叉"
  expect_contains "case7: 给两个选项" "$out" "merge --no-rebase"
  # A 的本地 commit SHA 应该没变（没被 rebase）
  a_sha_after="$( cd "$d/A" && git rev-parse HEAD )"
  expect_eq "case7: A 的 commit 没被 rebase（SHA 不变）" "$a_sha_before" "$a_sha_after"
}

############################################
# 8) --dry-run 不真 fetch
############################################
hdr "8) --dry-run 不真 fetch"
{
  fresh_setup "case8"
  d="$ROOT/case8"
  # B 推一个新提交
  mkcommit "$d/B" "b_dry.txt" "b dry"
  ( cd "$d/B" && git push -q origin main )
  # A 在 dry-run 前记录 origin/main 的 SHA（旧）
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
  # 直接写坏 upstream：让 main 跟踪 origin/does-not-exist（绕过 git 的校验）
  ( cd "$d/A"
    git config branch.main.remote origin
    git config branch.main.merge refs/heads/does-not-exist
  )
  out="$( cd "$d/A" && bash "$SYNC" 2>&1 )"; rc=$?
  expect_ne "case9: 非零退出" "0" "$rc"
  # 不应该说"已同步"
  if printf '%s' "$out" | grep -qF "已同步"; then fail "case9: 假报已同步"; else pass "case9: 没假报成功"; fi
}

############################################
# 10) 标准 ff-only 同步成功
############################################
hdr "10) 标准 ff-only 同步成功"
{
  fresh_setup "case10"
  d="$ROOT/case10"
  # B 推一个提交
  mkcommit "$d/B" "b_sync.txt" "b sync"
  ( cd "$d/B" && git push -q origin main )
  # A 干净，跑 safe_sync
  out="$( cd "$d/A" && bash "$SYNC" 2>&1 )"; rc=$?
  expect_eq "case10: exit 0" "0" "$rc"
  expect_contains "case10: ff-only" "$out" "ff-only"
  if [ -f "$d/A/b_sync.txt" ]; then pass "case10: A 拿到 B 的提交"; else fail "case10: A 没拿到"; fi
}

############################################
# 11) 两个 feature 分支依次合入主线，再同步到另一 clone
############################################
hdr "11) 两个 feature 合入 main，再同步到新 clone"
{
  fresh_setup "case11"
  d="$ROOT/case11"
  ( cd "$d/A"
    # feature/x
    git switch -q -c feature/x
    echo "x" > x.txt && git add x.txt && git commit -q -m "x"
    git push -q -u origin feature/x
    git switch -q main
    git merge -q --no-ff feature/x -m "merge feature/x"
    git push -q origin main
    # feature/y
    git switch -q -c feature/y
    echo "y" > y.txt && git add y.txt && git commit -q -m "y"
    git push -q -u origin feature/y
    git switch -q main
    git merge -q --no-ff feature/y -m "merge feature/y"
    git push -q origin main
  )
  # 新 clone C
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
    # 在主 worktree 里做未提交改动
    echo "uncommitted in main worktree" >> README.md
    # 开一个 worktree
    git worktree add -q "$d/A-wt1" -b feature/wt1
  )
  # 新 worktree 里 README 不应包含主 worktree 的未提交改动
  if grep -q "uncommitted in main worktree" "$d/A-wt1/README.md"; then
    fail "case12: worktree 泄漏了主 worktree 的未提交改动"
  else
    pass "case12: worktree 不受主 worktree 未提交改动影响"
  fi
  # 新 worktree 应该在自己的分支上
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
  out="$( cd "$d/A" && bash "$REMOTE_CHECK" 2>&1 )"; rc=$?
  expect_eq "case14: remote_check exit 0" "0" "$rc"
  expect_contains "case14: 报告 main 落后" "$out" "远端比你本地多"
  expect_contains "case14: CHANGED: yes" "$out" "CHANGED: yes"
}

############################################
# 15) 两个 feature 分别能合进 main，但彼此冲突
############################################
hdr "15) 两个 feature 分别能合 main，但彼此冲突"
{
  fresh_setup "case15"
  d="$ROOT/case15"
  ( cd "$d/A"
    git switch -q -c feature/a
    sed -i "" "s/# seed/# seed by A/" README.md
    git add README.md && git commit -q -m "a edits README"
    git push -q -u origin feature/a
  )
  ( cd "$d/B"
    git switch -q -c feature/b
    sed -i "" "s/# seed/# seed by B/" README.md
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
# 16) 检查完后 base/head 又变了 → 识别"已过期需重查"
############################################
hdr "16) 检查完后 base/head 变了 → 识别过期"
{
  fresh_setup "case16"
  d="$ROOT/case16"
  out1="$( cd "$d/A" && bash "$REMOTE_CHECK" 2>&1 )"
  expect_contains "case16: 第一次 CHANGED: no" "$out1" "CHANGED: no"
  mkcommit "$d/B" "late.txt" "late push"
  ( cd "$d/B" && git push -q origin main )
  cached="$( cd "$d/A" && git rev-list --left-right --count origin/main...main 2>/dev/null || echo '0 0' )"
  cached_behind="$(echo "$cached" | awk '{print $1}')"
  expect_eq "case16: 未重新 fetch 时缓存显示落后 0（旧数据）" "0" "$cached_behind"
  out2="$( cd "$d/A" && bash "$REMOTE_CHECK" 2>&1 )"
  expect_contains "case16: 重查后 CHANGED: yes" "$out2" "CHANGED: yes"
}

############################################
# 17) remote_check fetch 失败 → UNKNOWN，不假成功
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
# 18) remote_check 不在 git 仓库里 → 报错
############################################
hdr "18) remote_check 不在 git 仓库 → 报错"
{
  out="$( cd /tmp && bash "$REMOTE_CHECK" 2>&1 )"; rc=$?
  expect_ne "case18: 非零退出" "0" "$rc"
  expect_contains "case18: 提示不在仓库" "$out" "不在 Git 工作区"
}

############################################
# 注释：语义审查不测
#
# "语义审查不能用测试代替"这一条是情景评估，不是脚本能测的行为。
# 上面 1-18 只测机械行为（fetch、ahead/behind、ff-only、脏工作区拒绝、worktree 隔离等）。
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
