#!/usr/bin/env bash
#
# safe_sync.sh —— 安全地把远端最新代码同步到本地
#
# 原则：
#   - 工作区不干净（有未提交或未跟踪文件）→ 直接停下来，绝不替你 stash / reset。
#   - 干净时才 fetch + （必要时）pull --rebase。
#   - 绝不调用 force push / reset --hard / clean。
#
# 用法：
#   bash scripts/safe_sync.sh            # 真的执行
#   bash scripts/safe_sync.sh --dry-run  # 只打印会做什么，不动手
#
# 退出码：0=已同步或本来就最新；1=需要你先处理本地改动 / 出了冲突；2=硬错误。
#
set -u

DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

# ---------- 0. 确认在 Git 仓库里 ----------
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "✗ 当前目录不在 Git 仓库里。先 cd 到项目目录。"
  exit 2
fi
cd "$(git rev-parse --show-toplevel)"

# ---------- 1. 工作区干净吗？不干净就绝不往下走 ----------
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
  echo "  你可以二选一："
  echo "    A) 先把手上的活存个档：  git add -A && git commit -m \"说人话写干了啥\""
  echo "    B) 现在不想提交，先把改动收起来：  git stash push -m \"WIP\"  "
  echo "       （同步完再用  git stash pop  放回来）"
  echo
  echo "  千万别直接加参数让我强拉——那样可能把你刚写的东西盖掉。"
  exit 1
fi

# ---------- 2. 确认有 origin ----------
if ! git remote get-url origin >/dev/null 2>&1; then
  echo "✗ 这个仓库没有叫 origin 的远程仓库，没法同步。"
  echo "  先接上 GitHub：见 setup-checklist.md。"
  exit 2
fi

branch="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
if [ -z "$branch" ]; then
  echo "✗ 当前在 detached HEAD 上，不在任何分支。先 git switch <分支名> 再同步。"
  exit 1
fi

# ---------- 3. fetch（把远端最新信息拉下来，但不动你的工作区）----------
echo "→ 步骤 1/3：从 origin 拉取最新信息（fetch，不动你的文件）"
if [ "$DRY_RUN" -eq 1 ]; then
  echo "  [dry-run] 将要执行：git fetch origin"
else
  if ! git fetch origin; then
    echo "✗ git fetch 失败了。常见原因：网络不通、SSH 密钥没配好、没有权限。"
    echo "  可以先跑  ssh -T git@github.com  验证一下 SSH 通不通。"
    exit 2
  fi
fi
echo

# ---------- 4. 看领先/落后 ----------
upstream="$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)"
if [ -z "$upstream" ]; then
  echo "→ 当前分支 $branch 还没有 upstream。"
  echo "  第一次推送时用：git push -u origin $branch"
  echo "  （这次没有东西可同步，到此结束。）"
  exit 0
fi

counts="$(git rev-list --left-right --count '@{u}...HEAD' 2>/dev/null || echo '0 0')"
behind="$(echo "$counts" | awk '{print $1}')"
ahead="$(echo "$counts" | awk '{print $2}')"

echo "→ 步骤 2/3：和 $upstream 比一比"
if [ "$DRY_RUN" -eq 1 ]; then
  echo "  （注意：dry-run 没有真的 fetch，下面的领先/落后数字基于上一次 fetch 的信息，仅供参考）"
fi
echo "  你领先 $ahead 个提交，落后 $behind 个提交。"
echo

# ---------- 5. 落后才需要 pull --rebase ----------
if [ "$behind" -eq 0 ]; then
  echo "→ 步骤 3/3：基于当前信息，远端没有你还没有的新东西，不用拉。"
  if [ "$ahead" -gt 0 ]; then
    echo "  你本地领先 $ahead 个提交，记得适时 git push 推上去。"
  fi
  exit 0
fi

echo "→ 步骤 3/3：远端有 $behind 个你还没有的提交，执行 git pull --rebase"
echo "  （把你本地的新提交接在远端最新提交后面，历史更干净）"
if [ "$DRY_RUN" -eq 1 ]; then
  echo "  [dry-run] 将要执行：git pull --rebase origin $branch"
  exit 0
fi

if ! git pull --rebase origin "$branch"; then
  echo
  echo "✗ rebase 过程中出现了冲突，已经停下来了——你的文件没丢，只是处于"
  echo "  \"半合并\"状态，需要你（或你的 AI）照着 conflict-resolution.md 手动解决。"
  echo
  echo "  快速指引："
  echo "    1) git status            看哪些文件冲突了"
  echo "    2) 打开冲突文件，找 <<<<<<< ======= >>>>>>> 标记，留正确的、删标记"
  echo "    3) git add <解决好的文件>"
  echo "    4) git rebase --continue"
  echo "    5) 实在搞不定，随时可以 git rebase --abort 回到同步前的样子"
  echo
  echo "  详细说明见 references/conflict-resolution.md。"
  exit 1
fi

echo
echo "✓ 同步完成。现在你和 $upstream 一致了（本地若还有领先提交，记得 push）。"
