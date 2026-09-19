# ai-collaboration-guard

> 一套给 **AI 编程助手**用的代码协作防冲突守则（Skill）。你和朋友各自开着自己的 AI 写同一个项目时，
> 它指导 AI 在关键阶段主动联网检查对方的更新、读 diff 做审查、护着你们的活不丢。

**不是给老手看的 Git 大全，是给"什么都还没做过的小白"用的。** 装上之后，AI 会用大白话问清楚你的情况，
再带你走对应的协作流程——而不是逼你回答"你要 trunk-based 还是 feature-branch"。

---

## 它解决什么问题

两个人（或你和你自己的另一个 AI）同时改同一个项目，最容易出事的不是"Git 命令敲错"，而是：

- 你开工时看的远端状态，推上去时已经过时了（对方又推了东西）
- AI 一句 `--force` / `reset --hard` **把对方刚写的代码冲没**
- 有一半没写完的代码，同步时被悄悄丢掉
- "合并干净"或"测试绿"了，AI 就说"好了"——但逻辑其实是错的
- 朋友到底是"能直接推"还是"只能复制一份改"——搞混了流程
- `.env`、密钥不小心被提交上去

## 它怎么工作（AI 主动检查，不是后台服务）

这个 Skill 装上后，**你这边的 AI** 会在四个关键阶段主动做事：

1. **开工前**：跑 `preflight.sh`（看本地状态）+ `remote_check.sh`（真联网 fetch，看远端有没有新东西）。
2. **推送前**：再跑一次 `remote_check.sh`，远端主线有新提交就先合进功能分支。
3. **发起 PR 前**：AI 自己读 diff，判断逻辑 / 接口 / 数据迁移影响，写一句审查依据；有业务决策点才问你。
4. **对方 PR 要合入前**：**重新**查最新状态。只有 GitHub 勾了 "Dismiss stale approvals" 才会强制作废旧 approve；
   不管有没有这个设置，本 Skill 都要求重读最新 diff，再决定合不合。

**诚实边界**（别被宣传图骗了）：

- 这是 **Skill 指导宿主 AI 的行为**，不是后台服务。宿主 AI 不加载 / 没权限，就什么也读不到。
- 对方**没 push 到共享远端**的改动，你这边的 AI **根本看不到**——这是黑盒边界，不是 bug。
- 不装全天候监听、不接外部付费 AI 审查服务。
- 分支保护 / PR 必审 / CI 必过，要 owner 在 GitHub 设置后才存在；没配上就明说"靠你们自觉"。
- 不同 AI 工具对"调用自定义脚本 / gh CLI"的支持本仓库未逐一实测。
- 这套流程降低误覆盖和漏审风险，不承诺消除全部文本或逻辑冲突。

## 覆盖的 7 种情况

| 你现在的处境 | 流程 |
|---|---|
| 从零开始，先自己用 AI 写着备份 | 情景 1 · 单人起步 |
| 各自电脑，朋友能直接推（最常见） | 情景 2 · 两台电脑 + 协作者 |
| 两个人轮流用同一台电脑 | 情景 3 · 同机换着用 |
| 两个人 / 两个 AI 同时在一台机器并行干活 | 情景 4 · 同机并行（git worktree） |
| 朋友没写权限，只能复制一份改 | 情景 5 · fork + PR |
| 小项目、互相信任，想直接在主线上改 | 情景 6 · 直接改主分支（先讲风险） |
| 想"留个版本"发给别人 | 情景 7 · 打版本标签 |

## 安装

把这个文件夹放到你的 AI 编程工具识别为 Skill 的目录即可（以 Claude Code 为例）：

```bash
git clone https://github.com/Kaixuan-Gong/ai-collaboration-guard.git \
  ~/.claude/skills/ai-collaboration-guard
```

装完后，在项目里对 AI 说类似"我和朋友一起写这个项目，帮我把协作流程管起来"，它就会触发这套守则。
**依赖**：Git、Bash、Python3（解析 PR JSON）。`gh` CLI 可选——没有 gh 时 PR 状态标 UNKNOWN，由宿主 AI 引导你在网页上看。
完整的前置环境（git、SSH 密钥、GitHub 登录）见 `references/setup-checklist.md`。
Windows 需要 WSL 或 Git Bash；Linux 与各 AI 编程工具的脚本路径支持未实测。

## 里面有什么

```
ai-collaboration-guard/
├── SKILL.md                       # AI 入口：判断情景 + 安全红线 + 关键阶段检查循环
├── scripts/
│   ├── preflight.sh               # 开工前只读预检（本地缓存视角，不联网）
│   ├── remote_check.sh            # 真联网 fetch，三态 OK/ATTENTION/UNKNOWN
│   ├── safe_sync.sh               # 护住本地改动再同步（ff-only，分叉不替你 rebase）
│   └── conflict_check.sh          # 隔离临时 clone 里做文本冲突预判，不跑仓库代码
└── references/
    ├── safety-rules.md            # 安全红线清单
    ├── scenarios.md                # 7 套协作情景手册
    ├── conflict-resolution.md     # 冲突怎么解
    ├── setup-checklist.md          # 环境前置检查
    ├── ai-review-flow.md           # 语义审查义务（写给宿主 AI）
    └── gates-setup.md              # GitHub 分支保护 / PR / CI 怎么设
```

## 设计原则

- **大白话优先**：问用户的是"你和朋友用各自电脑吗"，不是术语。
- **拿不准就问**：关键信息不足时，AI 先问清楚再动手，不默认套流程。
- **默认不破坏**：不强推、不 reset、不 clean；破坏性操作前先说后果。
- **AI 主动检查**：开工 / 推前 / 合前主动联网，不是等用户想起来才查。
- **不说假话**：CI、分支保护能开就教你开，开不了就明说"目前靠你自己检查"；没 push 的改动看不到就直说。

## 验证与使用边界

在此仓库根目录运行：

```bash
bash tests/regression.sh
python3 tests/independent_probes.py .
```

本次 macOS 本地验证：回归 89 项断言通过，独立复核 12 项检查通过。测试只在临时 Git 仓库执行，不使用业务项目或生产数据。
PR 多页、畸形响应和权限失败使用协议模拟；本环境没有 gh，尚未完成真实登录账号的 PR API 集成测试。Linux、Windows 及不同 AI 工具的加载方式未逐一实测。

- Git >=2.38 与 Python3 才能运行隔离文本预演。自定义 merge 属性返回 LIMITED/非零，不能视作通过。
- 查询状态 OK 不等于代码审核通过；仍需 AI 读实际 diff、执行适用测试并核验正式审批和仓库保护。
- 本仓库提供指导与检查脚本，不会自动安装所有项目的 CI/保护规则，也不保证消除全部逻辑冲突。
- 脚本不是安全执行任意项目代码的沙箱。同一个工作目录内并发 Git 操作仍不受支持，应使用独立 worktree/clone。
- 仓库默认分支或 fork 目标不明确时，由 AI 先核验，必要时通俗询问用户，然后显式传入 `--base`。

你和朋友安装后，可以分别对各自的 AI 说：

> 请使用 ai-collaboration-guard 管理这个项目的协作。先检查现有仓库和对方已上传的更新，推荐适合我们的流程；开工、推送、合并前主动检查，遇到业务取舍再问我。不要改动其他项目。

## License

[MIT](LICENSE)
