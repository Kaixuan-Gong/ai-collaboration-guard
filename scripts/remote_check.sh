#!/usr/bin/env bash
#
# remote_check.sh —— 联网检查远端有没有新东西（机械检查，fail closed）
#
# 只读检查脚本：不做语义审查、不 merge、不 push、不改工作区。
# 职责：刚联网刷新后，远端到底变了没有，给宿主 AI 做下一步判断用。
#
# 原则：
#   - 先 git fetch --all --prune（真联网，不是读本地缓存）。
#   - 任何读取缺口（fetch 失败 / 解析不出 base / PR 读不到）→ STATUS: UNKNOWN 并 exit 2，
#     绝不因为没查到就当成"对方没改 / 一切 OK"。UNKNOWN 是最高优先级，盖过 ATTENTION。
#   - PR 用 gh api 拿结构化字段，python3 解析 JSON（不 sed/grep JSON）；
#     列目标 repo 的全部 open PR（分页 raw_decode 吃完整段），不只查自己分支。
#   - 不猜默认主线叫 main 还是 master；base 用 --base 显式传入，或从 origin/HEAD 符号引用
#     解析（并警示那是缓存），都没有就 UNKNOWN 让宿主 AI 问用户。
#   - "PR 读成功"不等于"审批合格"；有 open PR 需宿主 AI 核对 → ATTENTION。
#
# 用法：
#   bash "<skill安装目录>/scripts/remote_check.sh" [--base <remote>/<branch>]
#
# 退出码：
#   0 = STATUS: OK（联网成功、base 解析成功、PR 可读、无需要处理的新东西）
#   1 = STATUS: ATTENTION（有新提交 / 分叉 / open PR 需要人看一眼）
#   2 = STATUS: UNKNOWN（任何读取缺口，不要假装知道）
#
set -u
export GIT_OPTIONAL_LOCKS=0

# ---------- 参数 ----------
EXPLICIT_BASE=""
if [ "$#" -gt 2 ]; then
  echo "x 参数太多：$*"
  echo "  用法：remote_check.sh [--base <remote>/<branch>]"
  exit 2
fi
if [ "$#" -eq 1 ]; then
  case "$1" in
    -h|--help)
      echo "用法：remote_check.sh [--base <remote>/<branch>]"
      echo "只读联网检查远端更新；不 merge、不 push、不改工作区。"
      exit 0 ;;
    *)
      echo "x 未知参数：$1"
      echo "  用法：remote_check.sh [--base <remote>/<branch>]"
      exit 2 ;;
  esac
fi
if [ "$#" -eq 2 ]; then
  if [ "$1" != "--base" ]; then
    echo "x 未知参数：$1"
    echo "  用法：remote_check.sh [--base <remote>/<branch>]"
    exit 2
  fi
  EXPLICIT_BASE="$2"
fi

# ---------- 0. 在 git 工作区里 ----------
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "x 当前目录不在 Git 工作区里。"
  echo "STATUS: UNKNOWN"
  exit 2
fi
if ! cd "$(git rev-parse --show-toplevel 2>/dev/null)"; then
  echo "x 无法切到仓库根目录。"
  echo "STATUS: UNKNOWN"
  exit 2
fi

# ---------- 1. 本地有没有 remote ----------
if ! remotes="$(git remote 2>/dev/null)" || [ -z "$remotes" ]; then
  echo "x 这个仓库没有配置任何 remote。"
  echo "STATUS: UNKNOWN"
  exit 2
fi

# ---------- 2. 真联网 fetch ----------
echo "-> 联网刷新所有 remote（git fetch --all --prune）"
if ! git fetch --all --prune 2>&1; then
  echo "x git fetch --all 失败：网络不通 / 无权限 / SSH 密钥没配好。"
  echo "  我无法判断远端有没有新东西——这是 UNKNOWN，不是'对方没改'。"
  echo "STATUS: UNKNOWN"
  exit 2
fi
echo "  （以上是刚联网刷新的结果，不是上次 fetch 的缓存。）"
check_time="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo 'unknown')"
echo "  检查时间：$check_time"
echo

# ---------- 3. 当前分支 ----------
if ! branch="$(git symbolic-ref --quiet --short HEAD 2>/dev/null)"; then
  echo "! 当前处于 detached HEAD，不在任何分支上。"
  echo "STATUS: UNKNOWN"
  exit 2
fi
echo "-> 当前分支：$branch"

# ---------- 4. 当前分支 vs 它的 upstream ----------
up_info="$(git for-each-ref --format='%(upstream:remotename) %(upstream:remoteref)' "refs/heads/$branch" 2>/dev/null)"
up_rc=$?
upstream_status="no-upstream"
upstream_ref=""
behind=0
ahead=0
if [ "$up_rc" -ne 0 ]; then
  echo "x 读取 $branch 的 upstream 失败。"
  echo "STATUS: UNKNOWN"
  exit 2
fi
if [ -z "$up_info" ] || [ "$up_info" = " " ]; then
  echo "! 当前分支 $branch 没有跟踪任何远端分支。"
  echo "  （新功能分支还没 push；这不代表远端没新东西，只代表没法自动比。）"
else
  up_remote="$(echo "$up_info" | awk '{print $1}')"
  up_ref="$(echo "$up_info" | awk '{print $2}')"
  up_short="${up_ref#refs/heads/}"
  upstream_ref="$up_remote/$up_short"
  if ! counts="$(git rev-list --left-right --count "$upstream_ref...HEAD" 2>/dev/null)"; then
    echo "x 读取 $upstream_ref 与 HEAD 的差距失败。"
    echo "STATUS: UNKNOWN"
    exit 2
  fi
  behind="$(echo "$counts" | awk '{print $1}')"
  ahead="$(echo "$counts" | awk '{print $2}')"
  case "$behind" in ''|*[!0-9]*) echo "x behind 不是数字：$behind"; echo "STATUS: UNKNOWN"; exit 2 ;; esac
  case "$ahead"  in ''|*[!0-9]*) echo "x ahead 不是数字：$ahead";  echo "STATUS: UNKNOWN"; exit 2 ;; esac
  upstream_status="tracked"
  echo "-> 跟踪的远端：$upstream_ref"
  echo "  你领先 $ahead 个提交，落后 $behind 个提交。"
fi
echo

# ---------- 5. 远端分支清单（带 SHA，便于看到朋友分支的变化）----------
echo "-> 远端分支（<sha>  <ref>）："
if ! br_list="$(git for-each-ref --format='%(objectname)  %(refname:short)' refs/remotes 2>/dev/null)"; then
  echo "x 读取远端分支清单失败。"
  echo "STATUS: UNKNOWN"
  exit 2
fi
printf '%s\n' "$br_list" | sed 's/^/  /'
echo

# ---------- 6. 解析 base（PR 的目标分支），不猜 main/master ----------
# 最长前缀匹配 remote 名（remote 名可含斜杠，不能按第一个 / 切）。
longest_remote_match() {
  local ref="$1" best=""
  while IFS= read -r r; do
    [ -z "$r" ] && continue
    case "$ref" in
      "$r"/*)
        if [ ${#r} -gt ${#best} ]; then best="$r"; fi
        ;;
    esac
  done <<EOF
$remotes
EOF
  printf '%s' "$best"
}

base_ref=""
if [ -n "$EXPLICIT_BASE" ]; then
  base_ref="$EXPLICIT_BASE"
  echo "-> base 分支（显式传入）：$base_ref"
else
  head_sym="$(git symbolic-ref "refs/remotes/origin/HEAD" 2>/dev/null || true)"
  if [ -n "$head_sym" ]; then
    base_ref="${head_sym#refs/remotes/}"
    echo "-> base 分支（来自 origin/HEAD 符号引用）：$base_ref"
    echo "  ! origin/HEAD 是本地缓存的符号引用，不保证就是你这次 PR 的真实目标分支。"
    echo "  fork / trunk 改名 / 多人协作时，请用 --base <remote>/<branch> 显式指定。"
  fi
fi

if [ -z "$base_ref" ]; then
  echo "! 无法自动确定 base 分支（没有 origin/HEAD 符号引用，也没传 --base）。"
  echo "  请宿主 AI 问用户：'你这个功能要合到哪个分支？' 然后用 --base <remote>/<branch> 重跑。"
  echo "BASE: unknown"
  echo "STATUS: UNKNOWN"
  exit 2
fi

base_remote="$(longest_remote_match "$base_ref")"
if [ -z "$base_remote" ]; then
  echo "x base $base_ref 不以任何已配置 remote 开头（remote 名：$(echo "$remotes" | tr '\n' ' ')）。"
  echo "  特殊 fetch refspec 映射不被支持；请确认 --base 写法正确。"
  echo "BASE: unknown"
  echo "STATUS: UNKNOWN"
  exit 2
fi

# 校验 base_ref 存在于本地 remote-tracking 映射（这是刚 fetch 完的）
if ! git rev-parse --verify --quiet "refs/remotes/$base_ref" >/dev/null 2>&1; then
  echo "x base ref $base_ref 在本地 remote-tracking 映射里不存在。"
  echo "BASE: unknown"
  echo "STATUS: UNKNOWN"
  exit 2
fi

base_sha="$(git rev-parse "refs/remotes/$base_ref" 2>/dev/null)" || { echo "x 读取 base SHA 失败。"; echo "STATUS: UNKNOWN"; exit 2; }
head_sha="$(git rev-parse HEAD 2>/dev/null)" || { echo "x 读取 HEAD SHA 失败。"; echo "STATUS: UNKNOWN"; exit 2; }
echo "  base SHA：$base_sha"
echo "  head SHA：$head_sha"

# base 是否已包含 head 的所有提交？（即 head 是否落后于 base）
if ! base_counts="$(git rev-list --left-right --count "$base_ref...HEAD" 2>/dev/null)"; then
  echo "x 读取 $base_ref 与 HEAD 的差距失败。"
  echo "STATUS: UNKNOWN"
  exit 2
fi
base_behind="$(echo "$base_counts" | awk '{print $1}')"
base_ahead="$(echo "$base_counts" | awk '{print $2}')"
case "$base_behind" in ''|*[!0-9]*) echo "x base_behind 不是数字：$base_behind"; echo "STATUS: UNKNOWN"; exit 2 ;; esac
case "$base_ahead"  in ''|*[!0-9]*) echo "x base_ahead 不是数字：$base_ahead";  echo "STATUS: UNKNOWN"; exit 2 ;; esac

echo "-> base $base_ref vs 你当前分支："
echo "  base 比你多 $base_behind 个提交；你比 base 多 $base_ahead 个提交。"
if [ "$base_behind" -gt 0 ]; then
  echo "  ! base 有你还没有的提交。推 PR 前记得把 base 合进你的功能分支。"
fi
echo

# ---------- 7. PR 元数据（gh api，全部 open PR，python3 raw_decode 解析多页）----------
echo "-> PR 状态："
pr_repo_slug=""
if pr_remote_url="$(git config --get "remote.$base_remote.url" 2>/dev/null || true)"; then
  # 严格只认 GitHub SSH/HTTPS 格式；本地路径 / 其他 host 一律 UNKNOWN。
  pr_repo_slug="$(printf '%s' "$pr_remote_url" | python3 -c '
import sys, re
u = sys.stdin.read().strip()
m = re.fullmatch(r"(?:git@github\.com:|https://github\.com/)([A-Za-z0-9_-]+/[A-Za-z0-9_.-]+)", u)
if m:
    slug = m.group(1)
    if slug.endswith(".git"): slug = slug[:-4]
    if slug.split("/")[1] not in ("", ".", ".."): print(slug)
' 2>/dev/null || true)"
fi

pr_status="unknown"
if ! command -v gh >/dev/null 2>&1; then
  echo "  gh 未安装。PR 状态无法读取——这是 UNKNOWN，不是'没有 PR'。"
elif ! gh auth status >/dev/null 2>&1; then
  echo "  gh 未登录。PR 状态无法读取——这是 UNKNOWN。"
elif [ -z "$pr_repo_slug" ]; then
  echo "  base remote ($base_remote) 的 URL 不是 GitHub SSH/HTTPS 格式，不查询 GitHub API。PR 状态 UNKNOWN。"
else
  echo "  列出 $pr_repo_slug 的全部 open PR（分页）..."
  # 保留 gh 退出码：分页中途失败不能把已拿到的半截当全部。
  pr_json="$(gh api --paginate "repos/$pr_repo_slug/pulls?state=open&per_page=100" 2>/dev/null)"
  gh_rc=$?
  if [ "$gh_rc" -ne 0 ]; then
    echo "  gh api 失败（exit=${gh_rc}）。PR 状态 UNKNOWN。"
    pr_status="unknown"
  else
    parsed="$(printf '%s' "$pr_json" | python3 -c '
import sys, json
raw = sys.stdin.buffer.read().decode("utf-8", "strict")
if not raw.strip():
    print("MALFORMED"); sys.exit(0)
dec = json.JSONDecoder()
i, n = 0, len(raw)
items = []
while True:
    while i < n and raw[i] in " \t\r\n":
        i += 1
    if i >= n:
        break
    try:
        obj, end = dec.raw_decode(raw, i)
    except Exception:
        print("MALFORMED"); sys.exit(0)
    if not isinstance(obj, list):
        print("MALFORMED"); sys.exit(0)
    items.extend(obj)
    i = end
def is_sha(s):
    return isinstance(s, str) and len(s) == 40 and all(c in "0123456789abcdef" for c in s)
# 先全部校验字段，再一次性输出；任何一条不合法就整体 MALFORMED。
rows = []
for pr in items:
    try:
        num = pr["number"]
        bref = pr["base"]["ref"]; bsha = pr["base"]["sha"]
        href = pr["head"]["ref"];  hsha = pr["head"]["sha"]
    except Exception:
        print("MALFORMED"); sys.exit(0)
    if not isinstance(num, int):
        print("MALFORMED"); sys.exit(0)
    if not (isinstance(bref, str) and isinstance(href, str) and is_sha(bsha) and is_sha(hsha)):
        print("MALFORMED"); sys.exit(0)
    rows.append((num, bref, bsha, href, hsha))
if not rows:
    print("NONE")
else:
    for num, bref, bsha, href, hsha in rows:
        print("PR#%d base=%s(%s) head=%s(%s)" % (num, bref, bsha, href, hsha))
' 2>/dev/null || echo "PARSE_FAIL")"
    case "$parsed" in
      NONE)
        pr_status="none"
        echo "  没有 open PR。" ;;
      MALFORMED|PARSE_FAIL)
        pr_status="unknown"
        echo "  PR JSON 解析失败 / 字段不全 / 分页不一致。PR 状态 UNKNOWN。" ;;
      *)
        pr_status="open"
        echo "$parsed" | sed 's/^/    /'
        echo "  注意：列出 open PR != 审批合格。CI / review 状态需宿主 AI 逐个核对。" ;;
    esac
  fi
fi
echo "PR_STATUS: $pr_status"
echo

# ---------- 8. 总结论（UNKNOWN 最高优先级）----------
echo "=========================================="
echo "CHECK_TIME: $check_time"
echo "BASE: $base_ref ($base_sha)"
echo "HEAD: $head_sha"
echo "UPSTREAM: $upstream_ref (ahead=$ahead, behind=$behind)"
echo "PR_STATUS: $pr_status"

# UNKNOWN 最高优先级：任何读取缺口都不能 OK / 不能 ATTENTION 了事。
if [ "$pr_status" = "unknown" ]; then
  echo "CHANGED: unknown（PR 状态读取有缺口，不能宣称已检查完）"
  echo "STATUS: UNKNOWN"
  exit 2
fi

attention=0
if [ "$behind" -gt 0 ] || [ "$base_behind" -gt 0 ]; then
  echo "CHANGED: yes（远端有你本地没有的新提交）"
  attention=1
elif [ "$upstream_status" = "no-upstream" ]; then
  echo "CHANGED: unknown（当前分支没 tracking；base 比你多 $base_behind 个提交）"
  attention=1
else
  echo "CHANGED: no（tracking 与 base 都没有你本地没有的新提交）"
fi

if [ "$ahead" -gt 0 ] && [ "$behind" -gt 0 ]; then
  echo "! 你和 upstream 分叉了（既领先 $ahead 又落后 ${behind}）。"
  attention=1
fi

# 有 open PR 需要宿主 AI 看 → ATTENTION（读成功 != 审批合格）
if [ "$pr_status" = "open" ]; then
  echo "! 有 open PR 需要宿主 AI 核对（读成功 != 审批合格）。"
  attention=1
fi

# Also expose published work not yet represented by a PR. Listing refs alone
# must not silently count as reviewing another developer's branch.
while read -r published_sha published_ref; do
  [ -z "$published_sha" ] && continue
  if git merge-base --is-ancestor "$published_sha" "$base_sha"; then
    :
  else
    ancestor_rc=$?
    if [ "$ancestor_rc" -ne 1 ]; then
      echo "STATUS: UNKNOWN"
      exit 2
    fi
    echo "REVIEW_BRANCH: $published_ref ($published_sha) — 尚未进入目标基线，需 AI 查看差异"
    attention=1
  fi
done <<EOF
$br_list
EOF

echo "=========================================="
if [ "$attention" -eq 1 ]; then
  echo "STATUS: ATTENTION"
  exit 1
fi
echo "STATUS: OK"
exit 0
