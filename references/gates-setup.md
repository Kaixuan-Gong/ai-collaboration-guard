# GitHub 门禁配置与验证

Skill 不是后台服务，安装后不会自动保护任何仓库。只有具备对应管理权限的人在**用户明确授权的具体仓库**配置并回读成功，门禁才算强制生效。GitHub 页面和规则类型会变化，优先读当前设置与 API 返回，不照搬旧截图。

## 1. 配置前确认

- 仓库、准确主线和发布分支。
- 实际维护者是否有 Settings/Rules 权限。
- 协作者人数、真实 GitHub 账号与预期审批人。
- 仓库可见性与计划是否提供所需功能。
- 现有 Branch protection/rulesets、bypass actor 和 CI 状态。不要覆盖不理解的旧规则。
- 需要的 CI 命令能在 GitHub-hosted runner 安全运行，不依赖本地秘密或生产数据。

信息不明确时用日常语言询问，例如：“这是你能管理设置的仓库吗？”“合并你代码的人，是不是另一个真实 GitHub 账号？”

## 2. 双人项目推荐基线

对主线或等价发布分支：

- 必须通过 PR 合并。
- 至少一个真实的非作者批准。
- 新提交后要求重新审核（对应设置可用时启用 dismiss stale reviews）。无论服务器是否自动撤销旧批准，Skill 都要求 base/head 变动后重审。
- 必需的 CI 检查通过，且检查在每个相关 PR 真实触发。
- 禁止 force push 和删除受保护分支。
- 要求解决所有讨论；可用时要求分支在合并前更新。
- 谨慎配置 bypass。不要默认让管理员或机器人绕过全部规则；部署账号只给必需权限。

只有一名维护者时，不能设置“必须另一人批准”后再假装自己能满足。可先要求 PR/CI 或保留为工作约定，等真实协作者加入再启用审批要求。多人项目按团队实际增加审批人数，不机械按总人数设置。

## 3. CI：先运行，再设为必需

1. 识别项目现有测试/构建命令和安全运行条件。
2. 新增或修改 workflow 时，先通过普通 PR 让它在预期事件运行。
3. 验证 job 名、权限、触发范围和结果；避免仅在特定路径变化时运行，却又把该 check 设成所有 PR 的 required check。
4. 在规则中选择**已经产生成功 check run 的准确 context**。
5. 再用一个最小测试 PR 验证失败时确实阻止合并、成功且审批满足时允许合并。

不要用只执行 `echo` 的检查冒充业务测试。没有可运行测试时明确覆盖缺口，不把空壳设成质量门禁。

本 Skill 仓库可使用以下 CI（本仓库已公开这些可复跑命令）：

```yaml
name: skill-tests
on:
  push:
  pull_request:
permissions:
  contents: read
jobs:
  regression:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - run: bash tests/regression.sh
      - run: python3 tests/independent_probes.py .
```

这里选择 macOS 是因为本版本在 macOS 完成验收；Linux 兼容性尚未实测，不应先宣称多平台支持。

## 4. 配置方法

可使用仓库网页、GitHub CLI 或 API。操作页面可能显示 Rulesets 或 Branch protection；根据仓库当前界面选择。网页不是唯一方式，CLI/API 也必须使用登录账号的最小权限并保持请求/响应记录。

实施时先读现有完整配置，在副本上修改需要的字段，不用空对象或默认值整体覆盖未知规则。配置目标、bypass 和审批人数改变时，说明影响范围。

## 5. 必须回读

配置后立即回读并记录：

- 规则 ID/名称、enforcement 状态和匹配的目标分支。
- PR 要求和批准人数。
- dismiss-stale、last-push approval、conversation resolution 等实际字段。
- 必需检查的准确名称和 strict/up-to-date 设置。
- force push、deletion、linear history 与 bypass 状态。
- 仓库默认 merge 策略和合并后删除分支设置。

然后用测试 PR 实证：直接 push 被拒、未批准不能合并、失败检查不能合并、最新提交需要按规则重审。不能只看设置页有复选框就称为已验证。

## 6. 如何报告

- **强制生效**：权限允许，配置成功，API/页面回读一致，测试 PR 行为符合预期。
- **部分生效**：只验证了部分规则；逐项列出，不用总称“已保护”。
- **工作约定**：计划/权限不支持或用户未授权硬配置；说明需要人工执行的步骤。
- **UNKNOWN**：回读失败、登录态不明、API 不完整；停止宣称门禁可用。

失败时不关闭已有保护作为解决方案，不创建虚假账号或借用朋友凭证，不把作者自检算作独立批准。用户只授权方案设计时，不执行仓库设置变更。
