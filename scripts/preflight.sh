#!/usr/bin/env bash
#
# preflight.sh —— 开工前只读预检
#
# 绝对只读：不写文件、不 stash、不 add、不 fetch、不修改任何本地状态。
#
# 退出码：
#   0 = 干净，可继续往下走
#   1 = 有需要先处理的状态（脏工作区 / detached HEAD / 缺身份 / 无 upstream，至少一项）
#   2 = 不在 Git 仓库里，或其它无法继续运行的硬错误
#
set -u

# ---------- 0. 先确认确实在一个 Git 工作区里 ----------
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "✗ 当前目录不在 Git 仓库里（也不在某个仓库的子目录里）。"
  echo "  先 cd 到你的项目目录；如果还没初始化，照着 setup-checklist.md 走。"
  exit 2
fi

# 切到仓库根目录，保证无论在哪个子目录跑结果都一致（只读：不改用户文件）
repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

needs_attention=0

echo "== Git 开工预检（只读，不会改任何东西）=="
echo "仓库根目录：$repo_root"
echo

# ---------- 1. 当前分支 / 是否 detached HEAD ----------
branch="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
if [ -n "$branch" ]; then
  echo "当前分支：$branch"
else
  head_short="$(git rev-parse --short HEAD 2>/dev/null || echo '（还没有任何提交）')"
  echo "⚠ 当前处于 detached HEAD（不在任何分支上）：$head_short"
  echo "  直接在这个状态下改代码，提交很容易丢。先回到一个分支："
  echo "    git switch main        # 或你自己的主分支名"
  needs_attention=1
fi
echo

# ---------- 2. 工作区是否干净 ----------
# porcelain v1 每行两个状态码 XY：X=暂存区，Y=工作区。
#   '??' = 未跟踪文件；只要 X 或 Y 不是空格（M/A/D/R/C 等），就说明有没提交的活
#   —— 包括"已 git add 但还没 commit"的暂存改动，rebase 会因此拒绝，必须算脏。
untracked_count=0
dirty_count=0
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

if [ "$dirty_count" -eq 0 ] && [ "$untracked_count" -eq 0 ]; then
  echo "工作区：干净（没有没提交的改动）"
else
  echo "⚠ 工作区不干净："
  [ "$dirty_count" -gt 0 ] && echo "  - 有 $dirty_count 个文件改了还没提交"
  [ "$untracked_count" -gt 0 ] && echo "  - 有 $untracked_count 个未跟踪的新文件"
  echo "  先跑 git status 看一眼，再决定是先提交（git add + commit）还是先 stash。"
  echo "  我不会替你丢这些改动。"
  needs_attention=1
fi
echo

# ---------- 3. 远程仓库（remote）----------
echo "远程仓库："
if git remote >/dev/null 2>&1 && [ -n "$(git remote)" ]; then
  while IFS= read -r r; do
    url="$(git remote get-url "$r" 2>/dev/null || echo '（取不到地址）')"
    echo "  $r -> $url"
  done <<EOF
$(git remote)
EOF
else
  echo "  （没有配置任何 remote —— 还没接上 GitHub。见 setup-checklist.md）"
  needs_attention=1
fi
echo

# ---------- 4. upstream 与领先/落后 ----------
upstream="$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)"
if [ -z "$upstream" ]; then
  echo "当前分支还没有设置 upstream（不知道该和远端哪条分支比）。"
  echo "  第一次推送时用：git push -u origin <分支名>，以后就自动记住了。"
  needs_attention=1
else
  echo "upstream（跟踪的远端分支）：$upstream"
  # --left-right --count 的输出是 "左  右"，左=@{u}...HEAD 中的 @{u}，右=HEAD。
  # 即：第一个数 = 远端有而你没有的（落后），第二个数 = 你有而远端没有的（领先）。
  counts="$(git rev-list --left-right --count '@{u}...HEAD' 2>/dev/null || echo '0 0')"
  behind="$(echo "$counts" | awk '{print $1}')"
  ahead="$(echo "$counts" | awk '{print $2}')"
  if [ "$behind" -gt 0 ] && [ "$ahead" -gt 0 ]; then
    echo "你领先 $ahead 个提交、落后 $behind 个提交（远端也有新东西）。"
    echo "  开干前先 bash scripts/safe_sync.sh 同步一下。"
    needs_attention=1
  elif [ "$behind" -gt 0 ]; then
    echo "你落后远端 $behind 个提交，本地没有新提交。"
    echo "  建议先 bash scripts/safe_sync.sh 同步。"
    needs_attention=1
  elif [ "$ahead" -gt 0 ]; then
    echo "你领先远端 $ahead 个提交（本地有还没推上去的活）。"
    echo "  记得适时 git push 推上去，别只存在自己电脑上。"
  else
    echo "和远端完全一致。"
  fi
fi
echo

# ---------- 5. git 身份（提交会用什么署名）----------
have_name=1
have_email=1
if [ -z "$(git config user.name)" ]; then
  echo "⚠ git user.name 还没配置 —— 提交时没法署你的名字。"
  have_name=0
  needs_attention=1
else
  echo "git user.name：$(git config user.name)"
fi
if [ -z "$(git config user.email)" ]; then
  echo "⚠ git user.email 还没配置 —— 提交时没法署你的邮箱。"
  have_email=0
  needs_attention=1
else
  echo "git user.email：$(git config user.email)"
fi
if [ "$have_name" -eq 0 ] || [ "$have_email" -eq 0 ]; then
  echo "  配置方法（仓库级，只影响这个项目，不影响全局）："
  echo "    git config user.name  \"你的名字\""
  echo "    git config user.email \"你在 GitHub 上用的邮箱\""
fi
echo

# ---------- 6. 结论 ----------
if [ "$needs_attention" -eq 0 ]; then
  echo "✓ 一切正常，可以继续。"
  exit 0
else
  echo "⚠ 上面标了 ⚠ 的地方，先处理掉再继续。"
  exit 1
fi
