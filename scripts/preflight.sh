#!/usr/bin/env bash
#
# preflight.sh —— 开工前只读预检
#
# 绝对只读：不写文件、不 stash、不 add、不 fetch、不修改任何本地状态。
# 这是**本地缓存视角**，不查远端事实；要联网刷新远端状态用 remote_check.sh。
#
# 用法：用 Skill 的绝对路径调用，例如：
#   bash ~/.claude/skills/ai-collaboration-guard/scripts/preflight.sh
# （不要在用户项目里跑一个同名的本地脚本。）
#
# 退出码：
#   0 = 干净，可继续往下走
#   1 = 有需要先处理的状态（脏工作区 / detached HEAD / 缺身份 / 无 upstream，至少一项）
#   2 = 不在 Git 仓库里，或其它无法继续运行的硬错误（含参数不认识）
#
set -u
export GIT_OPTIONAL_LOCKS=0

# ---------- 参数校验：不接受任何参数；--help 也不能带额外参数 ----------
if [ "$#" -gt 0 ]; then
  if [ "$#" -gt 1 ] || { [ "${1:-}" != "-h" ] && [ "${1:-}" != "--help" ]; }; then
    echo "✗ 不认识的参数：$*"
    echo "  用法：preflight.sh（无参数；--help 单独用）"
    exit 2
  fi
  echo "用法：preflight.sh"
  echo "只读本地预检；不联网、不改文件。"
  exit 0
fi

# ---------- 0. 先确认确实在一个 Git 工作区里 ----------
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "✗ 当前目录不在 Git 仓库里（也不在某个仓库的子目录里）。"
  echo "  先 cd 到你的项目目录；如果还没初始化，照着 setup-checklist.md 走。"
  exit 2
fi

if ! repo_root="$(git rev-parse --show-toplevel 2>/dev/null)"; then
  echo "✗ 无法定位仓库根目录。"
  exit 2
fi
cd "$repo_root"

needs_attention=0

echo "== Git 开工预检（只读本地缓存，不联网；不会改任何东西）=="
echo "仓库根目录：$repo_root"
echo "提示：这是本地缓存视角，远端最新状态请用 remote_check.sh 联网刷新。"
echo

# ---------- 1. 进行中状态检查（merge/rebase/cherry-pick/revert/sequencer）----------
git_dir="$(git rev-parse --git-dir 2>/dev/null)" || { echo "✗ 无法定位 .git。"; exit 2; }
if [ -f "$git_dir/MERGE_HEAD" ]; then
  echo "⚠ 正在 merge 中途。先 git merge --abort 或解决冲突后 commit。"
  needs_attention=1
fi
if [ -f "$git_dir/CHERRY_PICK_HEAD" ]; then
  echo "⚠ 正在 cherry-pick 中途。先 git cherry-pick --abort 或 --continue。"
  needs_attention=1
fi
if [ -f "$git_dir/REVERT_HEAD" ]; then
  echo "⚠ 正在 revert 中途。先 git revert --abort 或 --continue。"
  needs_attention=1
fi
if [ -d "$git_dir/sequencer" ] && [ -n "$(ls -A "$git_dir/sequencer" 2>/dev/null)" ]; then
  echo "⚠ 正在 sequencer（cherry-pick/revert 序列）中途。"
  needs_attention=1
fi
if [ -d "$git_dir/rebase-merge" ] || [ -d "$git_dir/rebase-apply" ]; then
  echo "⚠ 正在 rebase 中途。先 git rebase --abort 或 --continue。"
  needs_attention=1
fi
[ "$needs_attention" -eq 1 ] && echo

# ---------- 2. 当前分支 / 是否 detached HEAD ----------
if branch="$(git symbolic-ref --quiet --short HEAD 2>/dev/null)"; then
  echo "当前分支：$branch"
else
  head_short="$(git rev-parse --short HEAD 2>/dev/null || echo '（还没有任何提交）')"
  echo "⚠ 当前处于 detached HEAD（不在任何分支上）：$head_short"
  echo "  直接在这个状态下改代码，提交很容易丢。先回到一个分支："
  echo "    git switch main        # 或你自己的主分支名"
  needs_attention=1
  branch=""
fi
echo

# ---------- 3. 工作区是否干净 ----------
if ! status_out="$(git status --porcelain 2>/dev/null)"; then
  echo "✗ git status 读取失败，无法判断工作区状态。"
  echo "  不要假设干净。先手动 git status 看一眼。"
  exit 2
fi

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
$status_out
EOF

if [ "$dirty_count" -eq 0 ] && [ "$untracked_count" -eq 0 ]; then
  echo "工作区：干净（没有没提交的改动）"
else
  echo "⚠ 工作区不干净："
  [ "$dirty_count" -gt 0 ] && echo "  - 有 $dirty_count 个文件改了还没提交"
  [ "$untracked_count" -gt 0 ] && echo "  - 有 $untracked_count 个未跟踪的新文件"
  echo "  先跑 git status 看一眼，再决定是先提交（git add 显式路径 + commit）还是先 stash。"
  echo "  我不会替你丢这些改动。"
  needs_attention=1
fi
echo

# ---------- 4. 远程仓库（remote）----------
echo "远程仓库："
if remotes="$(git remote 2>/dev/null)" && [ -n "$remotes" ]; then
  while IFS= read -r r; do
    url="$(git remote get-url "$r" 2>/dev/null || echo '（取不到地址）')"
    echo "  $r -> $url"
  done <<EOF
$remotes
EOF
else
  echo "  （没有配置任何 remote —— 还没接上 GitHub。见 setup-checklist.md）"
  needs_attention=1
fi
echo

# ---------- 5. upstream 与领先/落后（基于本地缓存，不联网）----------
if [ -n "$branch" ]; then
  up_info="$(git for-each-ref --format='%(upstream:remotename) %(upstream:remoteref)' "refs/heads/$branch" 2>/dev/null || true)"
  if [ -z "$up_info" ] || [ "$up_info" = " " ]; then
    echo "当前分支还没有设置 upstream（不知道该和远端哪条分支比）。"
    echo "  第一次推送时用：git push -u origin <分支名>，以后就自动记住了。"
    needs_attention=1
  else
    up_remote="$(echo "$up_info" | awk '{print $1}')"
    up_ref="$(echo "$up_info" | awk '{print $2}')"
    up_short="${up_ref#refs/heads/}"
    upstream_ref="$up_remote/$up_short"
    echo "upstream（跟踪的远端分支）：${upstream_ref}（本地缓存视角，未联网刷新）"
    if ! counts="$(git rev-list --left-right --count "$upstream_ref...HEAD" 2>/dev/null)"; then
      echo "⚠ 读取 $upstream_ref 与 HEAD 的差距失败（refs 读不到？）。"
      echo "  请让宿主 AI 使用它已解析的 Skill 绝对路径运行 remote_check.sh 联网刷新。"
      needs_attention=1
    else
      behind="$(echo "$counts" | awk '{print $1}')"
      ahead="$(echo "$counts" | awk '{print $2}')"
      case "$behind" in ''|*[!0-9]*) behind="" ;; esac
      case "$ahead"  in ''|*[!0-9]*) ahead=""  ;; esac
      if [ -z "$behind" ] || [ -z "$ahead" ]; then
        echo "⚠ ahead/behind 解析失败：counts='$counts'"
        needs_attention=1
      elif [ "$behind" -gt 0 ] && [ "$ahead" -gt 0 ]; then
        echo "你领先 $ahead 个提交、落后 $behind 个提交（远端也有新东西）。"
        echo "  请让宿主 AI 使用它已解析的 Skill 绝对路径运行 safe_sync.sh。"
        needs_attention=1
      elif [ "$behind" -gt 0 ]; then
        echo "你落后远端 $behind 个提交，本地没有新提交。"
        echo "  建议让宿主 AI 使用它已解析的 Skill 绝对路径运行 safe_sync.sh。"
        needs_attention=1
      elif [ "$ahead" -gt 0 ]; then
        echo "你领先远端 $ahead 个提交（本地有还没推上去的活）。"
        echo "  记得适时 git push 推上去，别只存在自己电脑上。"
      else
        echo "和远端完全一致（基于本地缓存；远端可能已变，开工前用 remote_check.sh 联网确认）。"
      fi
    fi
  fi
fi
echo

# ---------- 6. git 身份 ----------
have_name=1
have_email=1
if [ -z "$(git config user.name 2>/dev/null)" ]; then
  echo "⚠ git user.name 还没配置 —— 提交时没法署你的名字。"
  have_name=0
  needs_attention=1
else
  echo "git user.name：$(git config user.name)"
fi
if [ -z "$(git config user.email 2>/dev/null)" ]; then
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

# ---------- 7. 结论 ----------
if [ "$needs_attention" -eq 0 ]; then
  echo "✓ 本地预检通过（这是本地缓存视角；远端最新状态请用 remote_check.sh 确认）。"
  exit 0
else
  echo "⚠ 上面标了 ⚠ 的地方，先处理掉再继续。"
  exit 1
fi
