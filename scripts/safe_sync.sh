#!/usr/bin/env bash
#
# safe_sync.sh —— 安全地把远端最新代码同步到本地当前分支
#
# 设计原则（fail-closed）：
#   - 只同步当前分支真正跟踪的那个远端 ref（用 git for-each-ref 解析，不硬编码 origin）。
#   - 默认 fast-forward-only：本地没有自己的新提交时才快进合并；
#     一旦检测到分叉（你领先且落后），绝不静默 rebase，停下来让你选。
#   - 工作区不干净、正在 merge/rebase/cherry-pick/revert/sequencer、detached HEAD、unborn HEAD，
#     任何一种都直接停下，不替你 stash / reset / 改文件。
#   - 任何 git 命令失败都非零退出，不假设成功、不 fallback 成 "0 0"。
#   - --dry-run 全程不联网，只读本地缓存，并明说"不代表已验证远端"。
#
# 用法：
#   bash "<skill安装目录>/scripts/safe_sync.sh"            # 真执行
#   bash "<skill安装目录>/scripts/safe_sync.sh" --dry-run # 只读本地缓存，不联网
#
# 退出码：
#   0 = 已同步 / 本来就和远端一致 / 你领先但远端没新东西
#   1 = 需要你先处理（脏工作区 / 分叉需人工选 / 正在合并中途 / 无 upstream 等）
#   2 = 硬错误（不在仓库、参数不认识、fetch 失败、ff-only 失败等）
#
set -u
export GIT_OPTIONAL_LOCKS=0

DRY_RUN=0
if [ "$#" -gt 1 ]; then
  echo "x 参数太多：$*"
  echo "  用法：safe_sync.sh [--dry-run]"
  exit 2
fi
case "${1:-}" in
  "")          ;;
  --dry-run)   DRY_RUN=1 ;;
  -h|--help)
    echo "用法：safe_sync.sh [--dry-run]"
    echo "默认 ff-only 同步当前分支；分叉时停下让你选，不替你 rebase。"
    exit 0 ;;
  *)
    echo "x 未知参数：$1"
    echo "  用法：safe_sync.sh [--dry-run]"
    exit 2 ;;
esac

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "x 当前目录不在 Git 工作区里。先 cd 到项目目录。"
  exit 2
fi
if ! cd "$(git rev-parse --show-toplevel 2>/dev/null)"; then
  echo "x 无法切到仓库根目录。"
  exit 2
fi

git_dir="$(git rev-parse --git-dir 2>/dev/null)" || { echo "x 无法定位 .git 目录。"; exit 2; }

if [ -f "$git_dir/MERGE_HEAD" ]; then echo "x 仓库正在 merge 中途。"; exit 1; fi
if [ -f "$git_dir/CHERRY_PICK_HEAD" ]; then echo "x 仓库正在 cherry-pick 中途。"; exit 1; fi
if [ -f "$git_dir/REVERT_HEAD" ]; then echo "x 仓库正在 revert 中途。"; exit 1; fi
if [ -d "$git_dir/sequencer" ] && [ -n "$(ls -A "$git_dir/sequencer" 2>/dev/null)" ]; then echo "x 仓库正在 sequencer 中途。"; exit 1; fi
if [ -d "$git_dir/rebase-merge" ] || [ -d "$git_dir/rebase-apply" ]; then echo "x 仓库正在 rebase 中途。"; exit 1; fi

if ! branch="$(git symbolic-ref --quiet --short HEAD 2>/dev/null)"; then
  echo "x 当前处于 detached HEAD。"
  exit 1
fi
if ! git rev-parse --verify --quiet HEAD >/dev/null 2>&1; then
  echo "x 当前分支还没有任何提交（unborn HEAD）。"
  exit 1
fi

start_head="$(git rev-parse HEAD 2>/dev/null)" || { echo "x 读取 HEAD 失败。"; exit 2; }

if ! status_out="$(git status --porcelain 2>/dev/null)"; then
  echo "x git status 读取失败。"
  exit 2
fi
dirty_count=0; untracked_count=0
while IFS= read -r line; do
  [ -z "$line" ] && continue
  x="${line:0:1}"; y="${line:1:1}"
  if [ "$x" = "?" ]; then untracked_count=$((untracked_count+1))
  elif [ "$x" != " " ] || [ "$y" != " " ]; then dirty_count=$((dirty_count+1)); fi
done <<EOF
$status_out
EOF
if [ "$dirty_count" -gt 0 ] || [ "$untracked_count" -gt 0 ]; then
  echo "x 你有没保存的改动，先提交或 stash，我不会替你丢。"
  echo "  A) 按显式路径提交：git add path1 path2 && git commit -m \"...\""
  echo "  B) git stash push -m \"WIP 说明\""
  echo "     恢复时不要 pop 默认最新一条；用："
  echo "       git stash list"
  echo "       git rev-parse stash@{n}        # 拿稳定 SHA"
  echo "       git stash show -p <SHA>"
  echo "       git stash apply <SHA>"
  exit 1
fi

up_info="$(git for-each-ref --format='%(upstream:remotename) %(upstream:remoteref)' "refs/heads/$branch" 2>/dev/null || true)"
if [ -z "$up_info" ] || [ "$up_info" = " " ]; then
  echo "x 当前分支 $branch 没有 upstream。第一次推送：git push -u origin $branch"
  exit 1
fi
remote="$(echo "$up_info" | awk '{print $1}')"
up_ref="$(echo "$up_info" | awk '{print $2}')"
up_short="${up_ref#refs/heads/}"
if [ -z "$remote" ] || [ -z "$up_short" ]; then
  echo "x 无法解析 upstream：$up_info"; exit 2
fi
if ! git remote get-url "$remote" >/dev/null 2>&1; then
  echo "x upstream 指向的 remote \"$remote\" 不存在。"; exit 2
fi
upstream_ref="$remote/$up_short"
echo "-> 当前分支：$branch"
echo "-> 跟踪的远端：$upstream_ref"

echo "-> 步骤 1/3：git fetch ${remote}"
target_sha=""; remote_sha=""
if [ "$DRY_RUN" -eq 1 ]; then
  echo "  [dry-run] 不联网：只基于本地 remote-tracking 缓存，不代表已验证远端。"
  track_sha="$(git rev-parse "refs/remotes/$upstream_ref" 2>/dev/null || true)"
  if [ -n "$track_sha" ]; then target_sha="$track_sha"; else echo "  [dry-run] 本地缓存里没有 ${upstream_ref}。"; fi
else
  if ! git fetch "$remote"; then echo "x git fetch $remote 失败。"; exit 2; fi
  echo "-> 校验远端分支 ${remote}/$up_short 仍然存在"
  ls_remote_line="$(git ls-remote --exit-code "$remote" "refs/heads/$up_short" 2>/dev/null || true)"
  if [ -z "$ls_remote_line" ]; then
    echo "x 远端 ${remote} 已无 refs/heads/${up_short}（分支被删了）。"
    echo "  本地残留旧映射，不能据此说已同步。"; exit 2
  fi
  remote_sha="$(echo "$ls_remote_line" | awk '{print $1}')"
  case "$remote_sha" in ''|*[!0-9a-f]*) echo "x 无法解析远端 SHA：$ls_remote_line"; exit 2 ;; esac
  echo "  远端真实提交：$remote_sha"
  target_sha="$remote_sha"
fi
echo

counts="$(git rev-list --left-right --count "$upstream_ref...HEAD" 2>/dev/null || true)"
if [ -z "$counts" ]; then echo "x 读取 $upstream_ref 与 HEAD 差距失败。"; exit 2; fi
behind="$(echo "$counts" | awk '{print $1}')"
ahead="$(echo "$counts" | awk '{print $2}')"
case "$behind" in ''|*[!0-9]*) echo "x behind 不是数字：$behind"; exit 2 ;; esac
case "$ahead"  in ''|*[!0-9]*) echo "x ahead 不是数字：$ahead";  exit 2 ;; esac

if [ "$DRY_RUN" -ne 1 ]; then
  track_sha="$(git rev-parse "refs/remotes/$upstream_ref" 2>/dev/null || true)"
  if [ "$track_sha" != "$remote_sha" ]; then
    echo "x 不一致：ls-remote=${remote_sha} remote-tracking=${track_sha}。重跑本脚本。"
    exit 2
  fi
fi

echo "-> 步骤 2/3：和 $upstream_ref 比一比"
[ "$DRY_RUN" -eq 1 ] && echo "  （dry-run：本地缓存视角，未联网。）"
echo "  你领先 $ahead 个提交，落后 $behind 个提交。"
echo

if [ "$behind" -eq 0 ]; then
  echo "-> 步骤 3/3：远端没有新东西。"
  [ "$ahead" -gt 0 ] && echo "  你本地领先 $ahead 个提交，记得适时 push。"
  exit 0
fi

if [ "$ahead" -eq 0 ]; then
  echo "-> 步骤 3/3：ff-only 快进到 ${target_sha:-<远端SHA>}"
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "  [dry-run] 将要执行：git merge --ff-only ${target_sha:-<远端SHA>}"
    exit 0
  fi
  now_branch="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
  now_head="$(git rev-parse HEAD 2>/dev/null || true)"
  if [ "$now_branch" != "$branch" ] || [ "$now_head" != "$start_head" ]; then
    echo "x 开始同步后分支/HEAD 变了。停下。"; exit 2
  fi
  if ! recheck="$(git status --porcelain 2>/dev/null)"; then
    echo "x 二次 git status 读取失败。不要继续 merge。"; exit 2
  fi
  if [ -n "$recheck" ]; then
    echo "x 开始同步后工作区出现改动。停下。"; exit 2
  fi
  if ! git merge --ff-only "$target_sha"; then
    echo "x git merge --ff-only $target_sha 失败。"; exit 2
  fi
  echo "v 同步完成。$branch 已快进到 ${target_sha}。"
  exit 0
fi

echo "x 分叉了：领先 $ahead / 落后 ${behind}。我不替你 rebase。"
echo "  A) 推荐：git merge --no-edit $upstream_ref  （保留双方历史）"
echo "  B) 仅本地未发表分支：git rebase $upstream_ref"
exit 1
