# 给目标仓库初始化 GitHub 门禁（可执行 / 可适配流程）

这份文件教你（宿主 AI）怎么帮用户在他自己的 GitHub 仓库上设置**真正生效**的分支保护 / PR 必审 / CI 必过。
**重要边界**：这个 Skill 本身不是后台服务，它不能"装上就自动保护所有仓库"。
门禁是在 GitHub 仓库设置里配的，配了还要回读验证；配不上 / 套餐不支持，就明说"现在靠你们自觉"。

---

## 一、先搞清楚你要做什么

目标仓库是用户自己的（或用户是 owner / 有 Settings 权限）。
**不要**去碰别人的仓库，也不要碰用户没让你管的别的 repo。

先问用户两个问题：

1. "这个仓库是你自己的吗？你能进 Settings 吗？"（不是 owner 就别往下走，你设不了）
2. "你们几个人在协作？"（决定需要几个 approval）

---

## 二、推荐的门禁组合（按真实协作人数）

### 2 个真实协作者

- 主线（main）走 PR，禁止直接 push。
- 禁止 force push 到 main。
- 禁止删除 main。
- 要求至少 1 个 approval（另一个协作者）。
- CI（如果配了）必须通过。

### 3 个及以上

- 同上，但 approval 数量可以按团队习惯定（至少 1，大团队 2）。
- 可以加"要求最新 review"（新 push 让旧 approve 失效）。

### 只有 1 个人

- 不需要 PR / approval（你一个人）。
- 但可以开"禁止 force push 到 main"，防手滑。

---

## 三、怎么设（GitHub 网页为主，gh 可选）

### 3.1 进设置页

1. 打开仓库 `https://github.com/<owner>/<repo>`。
2. 点 **Settings**（最右边那排标签）。
3. 左边菜单点 **Branches**（在 "Code and automation" 下面）。
4. 点 **Branch protection rules** → **Add rule**。

### 3.2 规则怎么填

**Branch name pattern**：`main`（或你们的实际主线名）。

勾上这些（按你们人数和需求选）：

- ✅ **Require a pull request before merging** —— 禁止直接 push main。
  - 子选项 "Require approvals"：填需要几个 approval（2 人协作用 1）。
  - 子选项 "Dismiss stale pull request approvals when new commits are pushed"：**建议勾**——新 push 让旧 approve 失效，强制重审。
- ✅ **Require status checks to pass before merging**：
  - 先在 **Search for status checks** 里搜你真实存在的 CI 检查名（比如 `test` / `build`）。
  - **只勾你真的跑过、真的会变绿的检查**。勾一个永远不跑的，谁都合不进去。
  - 子选项 "Require branches to be up to date before merging"：建议勾。
- ✅ **Do not allow bypassing the above settings**：建议勾（让管理员也不能绕）。
- ❌ **Allow force pushes**：**不要勾**。
- ❌ **Allow deletions**：**不要勾**。

### 3.3 用 gh CLI（可选，不是必须）

如果你和用户都装了 `gh` 且登录了，可以：

```bash
# 列出现有规则
gh api repos/<owner>/<repo>/branches/main/protection

# （示例）设规则——参数很多，建议先在网页设一次，回读后再用 API 复现到别的仓库
```

**但 gh 不是必需的**。网页点一遍最直观，也不容易漏子选项。

---

## 四、设完必须回读验证（readback）

这一步**不能省**。设完规则，回到 `Settings → Branches` 页面，点开刚才那条规则，确认：

- Branch name pattern 确实是 `main`。
- "Require a pull request" 确实勾了。
- "Require approvals" 的数量确实是你要的。
- "Require status checks" 里列的检查名确实是真实存在的 CI job。

或者用 API 回读：

```bash
gh api repos/<owner>/<repo>/branches/main/protection
```

看返回的 JSON 里 `required_pull_request_reviews`、`required_status_checks` 字段是不是你设的值。

**回读不通过就等于没设**——GitHub 有时候因为套餐 / 权限静默忽略某些选项，不回读你以为设了其实没设。

---

## 五、如实区分：强制 vs 建议

| 情况 | 结论 |
|---|---|
| 规则设完、回读确认生效 | ✅ **强制生效**——直接 push main 会被拒，没 approval 合不了 |
| 规则没配上（免费套餐不支持某些选项） | ⚠️ **仅建议**——告诉用户"这个功能你的套餐没有，现在靠你们自觉 review" |
| 用户不是 owner / 没 Settings 权限 | ❌ **设不了**——告诉用户让 owner 去设 |
| CI 没配 / 配了没真跑通 | ❌ **不要**在规则里勾它当 required——会卡住所有 PR |

**绝不要**跟用户说"放心，装了这个 Skill 就有保护了"。Skill 只是指导你怎么设规则，
真正的强制是 GitHub 那边的规则在起作用。

---

## 六、CI 必须先真跑通，再设成 required

这是新手最容易踩的坑：

1. 先写一个最简单的 `.github/workflows/test.yml`，只跑 `echo "hello"`。
2. 推一个 commit，去 Actions 页面看它真的变绿了。
3. **确认变绿了之后**，再回 Branch protection rules 里把这个 check 勾成 required。

反过来做（先勾 required 再写 workflow）会导致：workflow 不存在 → 检查永远 pending → 所有 PR 合不了。

**不要**写这种路径过滤：

```yaml
on:
  push:
    paths: ['src/only-changed-by-nobody/']   # 错：永远不触发
```

---

## 七、最小权限原则

- 协作者只给 **Write** 权限，不要给 Admin（除非他真的要管 Settings）。
- 外部贡献者走 fork（情景 5），不要直接加成协作者。
- 机器人 / CI 账号用细粒度 token，不要用主人的主 token。

---

## 八、本 Skill 仓库自己的 CI

这个仓库（ai-collaboration-guard）如果要加 CI，就跑 `tests/regression.sh`：

```yaml
# .github/workflows/test.yml（示例，按需调整）
name: test
on: [push, pull_request]
jobs:
  regression:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: bash tests/regression.sh
```

**但这是可选的**。不加分也不影响 Skill 本身能用；加了就要真的让它跑绿。

**绝对不要**顺手去给用户没让你管的别的 repo 配 CI / 改保护规则。这份文件只适用于用户明确说"帮我在这个 repo 上设门禁"的那个 repo。

---

## 九、需要第二个真实账号来测审批时

如果用户想测试"两个账号互相 approve"的流程：

- 用**第二个真实的 GitHub 账号**（用户的朋友 / 同事的）。
- **不要**发明账号、不要用临时邮箱注册一个假的。
- **不要**把仓库设成只有一个账号能进——那样另一个人测不了。
- 测完记得把测试用的临时规则回滚，别留着影响正常协作。
