#!/usr/bin/env bash
#
# safe_sync.sh —— 安全地把远端最新代码同步到本地当前分支
#
# 设计原则（fail-closed）：
#   - 只同步当前分支真正跟踪的那个远端 ref（@{u}），不硬编码 origin。
#   - 默认 fast-forward-only：本地没有自己的新提交时才快进合并；
#     一旦检测到分叉（你领先且落后），绝不静默 rebase，停下来让你选。
#   - 工作区不干净、正在 merge/rebase/cherry-pick、detached HEAD、unborn HEAD，
#     任何一种都直接停下，不替你 stash / reset / 改文件。
#   - 任何 git 命令失败都非零退出，不假设成功。
#
# 用法：
#   bash <skill安装目录>/scripts/safe_sync.sh            # 真执行
#   bash <skill安装目录>/scripts/safe_sync.sh --dry-run  # 只打印会做什么，不动手
#
# 退出码：
#   0 = 已同步 / 本来就和远端一致 / 你领先但远端没新东西
#   1 = 需要你先处理（脏工作区 / 分叉需人工选 merge vs rebase / 正在合并中途 / 无 upstream 等）
#   2 = 硬错误（不在仓库、参数不认识、fetch 失败、ff-only 失败等）
#
set -u

DRY_RUN=0
case "${1:-}" in
  "")          ;;
  --dry-run)   DRY_RUN=1 ;;
  *)
    echo "✗ 未知参数：$1"
    echo "  用法：safe_sync.sh [--dry-run]"
    exit 2
    ;;
esac

# ---------- 0. 在 git 工作区里 ----------
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "✗ 当前目录不在 Git 工作区里。先 cd 到项目目录。"
  exit 2
fi
cd "$(git rev-parse --show-toplevel)"

git_dir="$(git rev-parse --git-dir)"

# ---------- 1. 状态预检：正在合并 / detached / unborn 都要先停 ----------
if [ -f "$git_dir/MERGE_HEAD" ]; then
  echo "✗ 仓库正在 merge 中途（.git/MERGE_HEAD 存在）。"
  echo "  先 git status 看完，解决完 git commit 或 git merge --abort，再同步。"
  exit 1
fi
if [ -f "$git_dir/CHERRY_PICK_HEAD" ]; then
  echo "✗ 仓库正在 cherry-pick 中途。"
  echo "  解决完 git cherry-pick --continue，或 git cherry-pick --abort，再同步。"
  exit 1
fi
if [ -d "$git_dir/rebase-merge" ] || [ -d "$git_dir/rebase-apply" ]; then
  echo "✗ 仓库正在 rebase 中途。"
  echo "  继续解决冲突后 git rebase --continue，或 git rebase --abort 回到同步前，再同步。"
  exit 1
fi

if ! git symbolic-ref --quiet --short HEAD >/dev/null 2>&1; then
  echo "✗ 当前处于 detached HEAD（不在任何分支上）。"
  echo "  先 git switch <你的分支> 再同步。"
  exit 1
fi
branch="$(git symbolic-ref --quiet --short HEAD)"

if ! git rev-parse --verify --quiet HEAD >/dev/null 2>&1; then
  echo "✗ 当前分支还没有任何提交（unborn HEAD），没有东西可同步。"
  echo "  先做第一次 commit 再说。"
  exit 1
fi

# ---------- 2. 工作区干净吗？不干净就绝不往下走 ----------
dirty_count=0
untracked_count=0
while IFS= read -r line; do
  [ -z "$line" ] && continue
  x="${line:0:1}"
  y="${line:1:1}"
  if [ "$x" = "?" ]; then
    untracked_count=$((untracked_count + 1))
  elif [ "$x" != " " ] || [ "$y" != " " ]; then
    dirty_count=$((dirty_count + 1))
  fi
done <<EOF
$(git status --porcelain)
EOF

if [ "$dirty_count" -gt 0 ] || [ "$untracked_count" -gt 0 ]; then
  echo "✗ 你有没保存的改动，先提交或 stash，我不会替你丢。"
  [ "$dirty_count" -gt 0 ] && echo "  - $dirty_count 个文件改了还没提交"
  [ "$untracked_count" -gt 0 ] && echo "  - $untracked_count 个未跟踪的新文件"
  echo
  echo "  先 git status + git diff 看一眼改了啥（确认没把 .env / 密钥纳进来），然后二选一："
  echo "    A) 按显式路径提交： git add path1 path2  &&  git commit -m \"说人话写干了啥\""
  echo "    B) 先把改动收起来：   git stash push -m \"<你的名字> WIP: 一句说明\""
  echo "       （同步完 git stash list 找到那条，git stash pop 放回来；pop 前先 git stash show -p 确认是自己的活）"
  echo
  echo "  我不会替你 stash / reset / clean。"
  exit 1
fi

# ---------- 3. 解析真正的 upstream（不硬编码 origin）----------
upstream="$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)"
if [ -z "$upstream" ]; then
  echo "✗ 当前分支 $branch 没有跟踪任何远端分支（@{u} 为空）。"
  echo "  第一次推送时用：git push -u origin $branch"
  echo "  （或你实际的远端名和分支名）。设好 upstream 之后再来同步。"
  exit 1
fi

# upstream 形如 origin/main 或 origin/feature/x；按第一个 / 切出 remote 和 ref
case "$upstream" in
  */*) remote="${upstream%%/*}"; up_ref="${upstream#*/}" ;;
  *)
    echo "✗ 无法解析 upstream 名字：${upstream}（形如 <remote>/<branch>）。"
    exit 2
    ;;
esac

# 顺便确认这个 remote 真的存在
if ! git remote get-url "$remote" >/dev/null 2>&1; then
  echo "✗ upstream 指向的 remote \"${remote}\" 不存在。"
  echo "  现有 remote：$(git remote | tr '\n' ' ')"
  exit 2
fi

echo "→ 当前分支：$branch"
echo "→ 跟踪的远端：${remote}/${up_ref}  (来自 @{u}，不是硬编码)"

# ---------- 4. fetch 该 remote ----------
echo "→ 步骤 1/3：git fetch ${remote}（不动你的工作区）"
if [ "$DRY_RUN" -eq 1 ]; then
  echo "  [dry-run] 将要执行：git fetch ${remote}"
else
  if ! git fetch "$remote"; then
    echo "✗ git fetch ${remote} 失败。常见原因：网络不通、SSH 密钥没配好、没有权限。"
    echo "  可先跑  ssh -T git@github.com  验证（如果远端是 GitHub）。"
    exit 2
  fi
fi
echo

# ---------- 5. 重新解析领先/落后（fetch 之后 refs 才新）----------
# --left-right --count 输出 "左 右"，左=$upstream，右=HEAD
# 即：第一个数=远端有而你没有的（落后），第二个数=你有而远端没有的（领先）
counts="$(git rev-list --left-right --count "$upstream...HEAD" 2>/dev/null || true)"
if [ -z "$counts" ]; then
  echo "✗ 读取 ${upstream} 与 HEAD 的差距失败（refs 读不到？）。"
  echo "  先 git fetch ${remote} 再手动 git status 看一眼。"
  exit 2
fi
behind="$(echo "$counts" | awk '{print $1}')"
ahead="$(echo "$counts" | awk '{print $2}')"

echo "→ 步骤 2/3：和 ${upstream} 比一比"
if [ "$DRY_RUN" -eq 1 ]; then
  echo "  （dry-run：如果上面没真 fetch，这个数字基于上一次 fetch 的旧信息，仅供参考）"
fi
echo "  你领先 $ahead 个提交，落后 $behind 个提交。"
echo

# ---------- 6. 决策：落后 0 / 可快进 / 分叉 ----------
if [ "$behind" -eq 0 ]; then
  echo "→ 步骤 3/3：远端没有你还没有的新东西，不用动。"
  [ "$ahead" -gt 0 ] && echo "  你本地领先 $ahead 个提交，记得适时 git push 推上去。"
  exit 0
fi

if [ "$ahead" -eq 0 ]; then
  # 只落后、本地没新提交 → 快进合并是安全的
  echo "→ 步骤 3/3：本地没有新提交，执行 git merge --ff-only ${upstream}"
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "  [dry-run] 将要执行：git merge --ff-only ${upstream}"
    exit 0
  fi
  if ! git merge --ff-only "$upstream"; then
    echo "✗ git merge --ff-only ${upstream} 失败。"
    echo "  按理本地没有新提交时应该能快进；如果这里失败了，多半是 repo 状态异常，"
    echo "  先 git status 看一眼，不要随便加参数。"
    exit 2
  fi
  echo
  echo "✓ 同步完成。现在 $branch 和 ${upstream} 一致了。"
  exit 0
fi

# 同时领先又落后 = 分叉。绝不替用户 rebase。
echo "✗ 分叉了：你本地有 $ahead 个提交，远端 ${upstream} 也有 $behind 个你还没有的提交。"
echo "  我不会替你 rebase（那会改写你已经推过的历史，可能让协作者的本地仓库坏掉）。"
echo
echo "  你二选一（想清楚再动手）："
echo
echo "  A) 经你（和协作者）审核后，做一个普通合并提交："
echo "       git merge --no-rebase ${upstream}"
echo "     （适合共享分支、已经推过的提交。历史里会多出一个 merge commit。）"
echo
echo "  B) 只在「这个分支只有你一个人在用、没人基于它干活」时，才可以 rebase："
echo "       git rebase ${upstream}"
echo "     （rebase 后本地历史被改写；如果你已经把这个分支推到远端，"
echo "       下次 push 必须用 git push --force-with-lease，这有风险，先和协作者说一声。）"
echo
echo "  选完按 conflict-resolution.md 处理可能的冲突，再正常 push。"
exit 1
