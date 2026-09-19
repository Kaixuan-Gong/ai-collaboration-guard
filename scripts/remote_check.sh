#!/usr/bin/env bash
#
# remote_check.sh —— 联网检查远端有没有新东西（机械检查，fail closed）
#
# 这是一个只读检查脚本：它自己不做语义审查、不 merge、不 push。
# 它的职责是"刚联网刷新后，远端到底变了没有"，给宿主 AI 做下一步判断用。
#
# 关键原则：
#   - 一定先 git fetch --all --prune（真联网，不是读本地缓存）。
#   - fetch 失败 / 无网络 / 无权限 → 输出 STATUS: UNKNOWN 并非零退出，
#     **绝不**因为没查到就当成"对方没改"。
#   - 不修改工作区、不 merge、不 rebase、不 push。
#   - PR 元数据不依赖 gh；gh 可用就调它读真实 PR，不可用就明说"PR 状态需宿主 AI 用网页/API 核对"。
#
# 用法：
#   bash <skill安装目录>/scripts/remote_check.sh
#
# 退出码：
#   0 = 成功联网刷新并给出结论（CHANGED: yes/no）
#   1 = 有需要人看一眼的情况（分叉、无 upstream、PR 状态 UNKNOWN 等）
#   2 = 硬错误（不在仓库、参数不认识、fetch 失败等）
#
set -u

# ---------- 参数 ----------
case "${1:-}" in
  "" ) ;;
  -h|--help )
    echo "用法：remote_check.sh"
    echo "只读联网检查远端更新；不 merge、不 push、不改工作区。"
    exit 0 ;;
  *)
    echo "✗ 未知参数：$1"
    echo "  用法：remote_check.sh [-h]"
    exit 2 ;;
esac

# ---------- 0. 在 git 工作区里 ----------
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "✗ 当前目录不在 Git 工作区里。"
  echo "STATUS: UNKNOWN"
  exit 2
fi
cd "$(git rev-parse --show-toplevel)"

# ---------- 1. 先看本地有没有 remote ----------
if ! git remote >/dev/null 2>&1 || [ -z "$(git remote)" ]; then
  echo "✗ 这个仓库没有配置任何 remote。"
  echo "STATUS: UNKNOWN"
  exit 1
fi

# ---------- 2. 真联网 fetch ----------
echo "→ 联网刷新所有 remote（git fetch --all --prune）"
if ! git fetch --all --prune 2>&1; then
  echo "✗ git fetch --all 失败：网络不通 / 无权限 / SSH 密钥没配好。"
  echo "  我无法判断远端有没有新东西——这是 UNKNOWN，不是'对方没改'。"
  echo "STATUS: UNKNOWN"
  exit 2
fi
echo "  （以上是刚联网刷新的结果，不是上次 fetch 的缓存。）"
echo

# ---------- 3. 当前分支 vs 它的 upstream ----------
branch="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
if [ -z "$branch" ]; then
  echo "⚠ 当前处于 detached HEAD，不在任何分支上。"
  echo "STATUS: UNKNOWN"
  exit 1
fi

echo "→ 当前分支：$branch"

upstream="$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)"
if [ -z "$upstream" ]; then
  echo "⚠ 当前分支 $branch 没有跟踪任何远端分支。"
  echo "  第一次推送时用：git push -u origin $branch"
  echo "CHANGED: unknown"
  echo "STATUS: UNKNOWN"
  exit 1
fi

case "$upstream" in
  */*) remote="${upstream%%/*}"; up_ref="${upstream#*/}" ;;
  *)   echo "✗ 无法解析 upstream：$upstream"; echo "STATUS: UNKNOWN"; exit 2 ;;
esac

counts="$(git rev-list --left-right --count "$upstream...HEAD" 2>/dev/null || true)"
if [ -z "$counts" ]; then
  echo "✗ 读取 $upstream 与 HEAD 的差距失败。"
  echo "STATUS: UNKNOWN"
  exit 2
fi
behind="$(echo "$counts" | awk '{print $1}')"
ahead="$(echo "$counts" | awk '{print $2}')"

echo "→ 跟踪的远端：${remote}/${up_ref}"
echo "  你领先 $ahead 个提交，落后 $behind 个提交。"
echo

# ---------- 4. 远端都有哪些分支 ----------
echo "→ 远端分支（git branch -r）："
git branch -r | sed 's/^/  /'
echo

# ---------- 5. 远端 main / 默认主线是否比本地 main 新 ----------
# 先猜默认主线叫什么
default_main="main"
if git show-ref --verify --quiet "refs/remotes/origin/main"; then
  default_main="main"
elif git show-ref --verify --quiet "refs/remotes/origin/master"; then
  default_main="master"
fi
local_main="main"
if ! git show-ref --verify --quiet "refs/heads/$local_main"; then
  local_main="master"
fi
main_behind=0

if git show-ref --verify --quiet "refs/remotes/origin/$default_main"; then
  main_counts="$(git rev-list --left-right --count "origin/$default_main...$local_main" 2>/dev/null || true)"
  if [ -n "$main_counts" ]; then
    main_behind="$(echo "$main_counts" | awk '{print $1}')"
    main_ahead="$(echo "$main_counts" | awk '{print $2}')"
    echo "→ 远端 ${default_main} vs 本地 ${local_main}："
    echo "  远端比你本地多 ${main_behind} 个提交；你本地比远端多 ${main_ahead} 个提交。"
    if [ "$main_behind" -gt 0 ]; then
      echo "  ⚠ 远端主线有你本地没有的提交。开工前 / 推 PR 前记得把主线合进你的功能分支。"
    fi
  fi
fi
echo

# ---------- 6. PR 元数据（gh 可选）----------
echo "→ PR 状态："
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  origin_url="$(git remote get-url origin 2>/dev/null || true)"
  # 从 origin URL 提取 owner/repo（支持 git@github.com:owner/repo.git 和 https://...）
  repo_slug="$(echo "$origin_url" | sed -E 's#^(git@github.com:|https://github.com/)##; s#\.git$##')"
  if [ -n "$repo_slug" ] && echo "$repo_slug" | grep -q '/'; then
    echo "  （gh 可用，读取 $repo_slug 的 open PR）"
    if gh pr list --repo "$repo_slug" --state open 2>/dev/null; then
      :
    else
      echo "  ⚠ gh pr list 失败（可能没有权限或网络问题）。PR 状态标 UNKNOWN。"
      echo "PR_STATUS: UNKNOWN"
    fi
  else
    echo "  ⚠ 无法从 origin URL 解析 owner/repo（${origin_url}）。PR 状态标 UNKNOWN。"
    echo "PR_STATUS: UNKNOWN"
  fi
else
  echo "  gh 不可用或未登录。PR 状态需宿主 AI 用网页或 API 核对——不要假装你知道 PR 是绿是红。"
  echo "PR_STATUS: UNKNOWN"
fi
echo

# ---------- 7. 总结论 ----------
echo "=========================================="
if [ "$behind" -gt 0 ] || [ "$main_behind" -gt 0 ]; then
  echo "CHANGED: yes （远端有你本地没有的新提交；这是刚 fetch 完的真实结果）"
else
  echo "CHANGED: no （远端没有新提交；这是刚 fetch 完的真实结果）"
fi
echo "=========================================="

# 分叉（既领先又落后）要提醒人看一眼
if [ "$ahead" -gt 0 ] && [ "$behind" -gt 0 ]; then
  echo "⚠ 注意：你和远端分叉了（既领先 $ahead 又落后 $behind）。"
  echo "  不要直接 push；按 safe_sync.sh 的提示选 merge 或 rebase。"
  exit 1
fi
exit 0
