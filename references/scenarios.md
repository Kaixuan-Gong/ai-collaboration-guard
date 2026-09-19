# 协作情景手册（6 套流程，对号入座）

这份手册和 SKILL.md 末尾的"情景速查"表一一对应。**先读那张大表判断你属于哪种，再翻到对应小节。**
不同情景的命令和节奏是真的不一样，别把情景 2 的命令换个名字套到情景 4 上。

约定：
- 下面所有命令里，`your-name`、`you@example.com`、`~/projects/demo`、`yourname/what-you-do` 都是占位符，换成你自己的。
- 分支名一律用"谁在做 + 做什么"，例如 `zhangkai/login-page`，别用 `test`、`wip`、`123`。
- 开工前先跑 `bash scripts/preflight.sh`，脏了就先按它说的处理。

---

## 情景 1：单人起步备份（从零开始，还没朋友加入）

**对应哪种大白话答案**："还一行代码都没有、想从零开始" + "现在就我一个人先用 AI 写"。

**什么时候用**：你刚想到一个点子，自己先拿 AI 写着玩，想把代码放到网上备份、以后万一电脑坏了不丢。**这是最简单的起步流程**，等朋友要加入了再切到情景 2。

### 第一次怎么搭

```bash
# 1. 建项目目录（如果还没有）
mkdir -p ~/projects/demo
cd ~/projects/demo
git init -b main          # 默认主分支叫 main（老版本 git 用 git init 然后 git checkout -b main）

# 2. 写个 .gitignore（第一次提交前一定要有，见 setup-checklist.md）
#    把 node_modules/、.env、venv/、__pycache__/、.DS_Store、dist/ 都挡上

# 3. 配置你的身份（只对这个仓库生效；想全局配就去掉 --local）
git config --local user.name  "your-name"
git config --local user.email "you@example.com"

# 4. 第一次提交
git add .
git commit -m "init: 项目起步"

# 5. 在 GitHub 网页上新建一个空仓库（不要勾 README、不要勾 .gitignore，避免和本地冲突），
#    然后照着 GitHub 页面上"…or push an existing repository from the command line"那一段：
git remote add origin git@github.com:your-name/demo.git
git push -u origin main
```

### 平时每天怎么同步 / 提交 / 推

单人项目其实没有"和别人同步"的问题，节奏就是**小步提交、经常备份**：

```bash
bash scripts/preflight.sh
# 改完一段能跑的代码就：
git add -A
git commit -m "说人话写这次干了啥，例如: 加了登录页的表单校验"
git push origin main
```

**规则**：别攒一大堆改动一次 commit。每做完一个能跑的小功能就 commit 一次，出问题好回退。

### 怎么合并

单人项目没有"合并别人的活"这回事，不需要 PR。直接在 main 上提交就行。

### 冲突了怎么办

单人一般不会冲突。真出现了（比如你在两台电脑上都改了），照 conflict-resolution.md 处理。

### 什么情况下不该用这个情景

- 朋友要加入一起写了 → 切到情景 2 / 3 / 4。
- 你已经在别的地方有代码了 → 不要重新 init，直接 clone 那个仓库（见情景 2）。
- 要给别人发布一版 / 打版本号 → 见情景 6。

---

## 情景 2：两台电脑 + 协作者（最常见的主流程）

**对应哪种大白话答案**："已经有代码了" + "各自用自己的电脑" + "朋友能直接往仓库推代码" + "每个人单独做一块、做完再合起来"。

**什么时候用**：你和朋友各自有电脑，你已经把他加成了 GitHub 仓库的协作者。这是**推荐的多人协作姿势**：每人开自己的分支，做完开 PR，另一个人看一眼再合。

### 第一次怎么搭（你是仓库 owner）

```bash
# 1. 你这边先有一个本地仓库（同情景 1 的前 5 步），main 分支已推到 GitHub。

# 2. 在 GitHub 网页上把朋友加成协作者（不需要 gh CLI）：
#    ① 打开 https://github.com/your-name/demo
#    ② 点上面那一排标签里的 "Settings"（在最右边）
#    ③ 左边菜单点 "Collaborators"（有的版本人叫 "Collaborators and teams"）
#    ④ 点 "Add people"，输入朋友的 GitHub 用户名或邮箱，发邀请
#    ⑤ 朋友要去他自己的邮箱 / GitHub 通知里点接受邀请，加完才算数
```

朋友那边：

```bash
# 3. 朋友在自己电脑上把仓库 clone 下来
cd ~/projects
git clone git@github.com:your-name/demo.git
cd demo
git config --local user.name  "friend-name"
git config --local user.email "friend@example.com"
```

### 平时每天怎么干（两边都一样）

**开工前先同步 + 开新分支**：

```bash
cd ~/projects/demo
bash scripts/preflight.sh
bash scripts/safe_sync.sh          # 先把远端最新拉下来（它会先检查你本地干不干净）

# 开一个"谁做什么"的分支
git switch -c friend-name/what-you-do     # 例如 friend-name/login-page
# 例如：git switch -c zhangkai/login-page
```

**改完一段就提交、推分支**：

```bash
git add -A
git commit -m "login: 加了手机号输入框和校验"
git push -u origin friend-name/what-you-do
```

`-u` 第一次写，以后直接 `git push` 就行。

### 怎么合并（开 PR，不是本地直接合）

1. 推完分支后，GitHub 仓库首页会跳出一行黄色提示 "*friend-name/what-you-do had recent pushes*"，右边一个 "Compare & pull request" 按钮，点它。
2. 填个标题和说明：这次改了什么、为什么。点 "Create pull request"。
3. **喊另一个人来看一眼**：不是合 PR 的人自己点 merge。对方在 PR 页面：
   - 先去 "Files changed" 标签看 diff；
   - 能跑的话最好把分支拉到本地跑一下（`git fetch origin` + `git switch friend-name/what-you-do`）；
   - 没问题就回 "Conversation" 标签点 "Review changes" → "Approve"。
4. 点 "Merge pull request" → "Confirm merge"。合完后分支就可以删了。

**关于 CI / 分支保护**：只有 owner 在 GitHub 网页 `Settings → Branches` 里设了"要求 PR 才能合 main"，直接推 main 才会被拦。没设就是没设，别跟朋友说"系统会自动拦你"。

### 冲突了怎么办

PR 页面如果显示 "This branch has conflicts"，或者你本地 rebase 时炸了，照 conflict-resolution.md 处理。**不要**在 PR 页面一键 "Resolve conflicts" 完事就合——合完一定要真的跑一下代码。

### 什么情况下不该用这个情景

- 朋友点绿色 Code 按钮发现根本推不回去（没写权限）→ 切到情景 4。
- 两个人其实是轮流用同一台电脑 → 切到情景 3。
- 项目很小、就俩人互相信任、嫌 PR 麻烦 → 看情景 5，但先读它开头的风险说明。
- 你自己一个人玩、还没人加入 → 情景 1 更简单。

---

## 情景 3：同一台电脑，两个人轮流用

**对应哪种大白话答案**："两个人轮流用同一台电脑"（比如合租室友、夫妻共用一台开发机）。

**什么时候用**：代码仓库在一台电脑上，但 A 白天用、B 晚上用，两人的 GitHub 账号不一样。**核心风险**：两个人的提交署名会混在一起、A 的未提交改动会被 B 带着走。

### 第一次怎么搭

仓库本身还是在 GitHub 上（远端同情景 2），但**本地配置要按人切**：

```bash
cd ~/projects/demo

# 给每个用户单独配一个 local 身份（不要配 global，否则换人就得改全局）
# A 用时：
git config --local user.name  "your-name"
git config --local user.email "you@example.com"

# B 用时：
git config --local user.name  "friend-name"
git config --local user.email "friend@example.com"
```

> 注意：`--local` 只影响这个仓库。这是**故意的**——同机两个人都用这台机器跑别的项目，别互相污染。

### 平时怎么干：换人之前必须做一件事

**换人前 30 秒检查（最重要）**：

```bash
bash scripts/preflight.sh
```

看到工作区干净 → 直接换下一个人用。
看到还有没提交 / 未跟踪文件 → **二选一，别留着过夜**：

```bash
# 选 A：把手上的活存个档，下次接着干
git add -A && git commit -m "wip: 还没写完的一半"

# 选 B：先收起来，别提交半成品
git stash push -m "your-name 没写完的东西"
# 下次回来 git stash list 看有哪些，git stash pop 放出来
```

**然后才换身份**：

```bash
git config --local user.name  "下一个人的名字"
git config --local user.email "下一个人的邮箱"
bash scripts/safe_sync.sh    # 换人后先同步一下远端
```

### 怎么合并

跟情景 2 一样：各自开 `yourname/what-you-do` 分支，开 PR，互相 review。
**别因为在同一台电脑上就图省事直接 push 到 main**——本地分支看起来是连着的，但 GitHub 上的历史还是乱。

### 冲突了怎么办

照 conflict-resolution.md。同机协作最常见的冲突原因就是"换人前没 stash，两个人的改动叠在工作区里"——养成换人前跑 preflight 的习惯，能躲开 90% 的坑。

### 什么情况下不该用这个情景

- 其实是两台电脑远程协作 → 情景 2。
- 你是其中一个人的电脑，另一个人远程连上来 SSH / 远程桌面写代码 → 本质还是"多人共用一个工作区"，本情景的"换人前 stash / commit + 切身份"规则照样适用。

---

## 情景 4：朋友没有写权限（fork + PR）

**对应哪种大白话答案**："朋友没法直接推回我们的仓库，只能复制一份自己改"。

**什么时候用**：你是 owner，朋友是外部贡献者（不是你私人朋友，或者你还不想把他加成协作者）。他要先把你的仓库**复制一份到他自己账号下**（这叫 fork），改完再给你发 PR。

### 第一次怎么搭（两边各做一步）

朋友这边：
1. 打开你的仓库 `https://github.com/your-name/demo`，右上角点 **"Fork"** 按钮，让它在他自己账号下生成一份 `friend-name/demo`。
2. 把 fork clone 到本地：

```bash
git clone git@github.com:friend-name/demo.git
cd demo
git config --local user.name  "friend-name"
git config --local user.email "friend@example.com"

# 关键：把"原作者的仓库"加为 upstream，不然没法同步你的更新
git remote add upstream git@github.com:your-name/demo.git
git remote -v          # 应该看到 origin=自己的fork, upstream=原仓库
```

### 平时怎么干（朋友侧）

每次开工前**先同步原仓库的最新代码**（这是 fork 工作流最容易忘的一步）：

```bash
git fetch upstream
git switch main
git rebase upstream/main     # 把自己 main 上的小改动接到原仓库最新后面；干净时也可用 git merge upstream/main
# 然后开新分支干活
git switch -c friend-name/what-you-do
```

改完推到**自己的 fork**（不是原仓库）：

```bash
git add -A
git commit -m "..."
git push origin friend-name/what-you-do
# origin 在这里 = 朋友自己的 fork，不是原仓库
```

### 怎么合并

1. 朋友在自己 fork 的 GitHub 页面上，会看到 "Compare & pull request" 按钮——**注意方向**：base repository 要选 `your-name/demo` 的 `main`，head repository 是 `friend-name/demo` 的 `friend-name/what-you-do`。
2. 你（原作者）去 `your-name/demo` 的 Pull requests 标签页，就能看到这个 PR。review、讨论、合并，跟情景 2 一样。

### 朋友怎么持续同步原仓库的更新（标准三步）

原仓库经常在变，朋友本地要跟上：

```bash
git fetch upstream                 # ① 把原仓库最新信息拉下来
git switch main                    # ② 切回自己的 main
git rebase upstream/main           # ③ 把 main 接到原仓库最新提交后面
git push origin main               # 顺手把自己 fork 的 main 也更新（可选，但推荐）
```

以后再开新功能分支，就从最新的 main 开，不会和原仓库差太远。

### 冲突了怎么办

照 conflict-resolution.md。fork 工作流里冲突最常见的原因就是"忘了上面这三步，自己的 main 落后原仓库一两个月"。

### 什么情况下不该用这个情景

- 你和朋友关系很铁、也信得过 → 直接走情景 2 把他加成协作者，省掉 fork 这一层。
- 你是单人项目、根本没人给你发 PR → 用情景 1。
- 朋友其实有写权限但你忘了 → 重新走情景 2。

---

## 情景 5：直接在主分支上改（先讲清楚风险）

**对应哪种大白话答案**："小项目、互相信任，想大家都直接在同一条主线上改"。

**先把风险说在前面**：这是所有流程里最容易"互相覆盖"的一种。它适合**两个人都经常在线、改动都很小、出了问题能马上拉群骂一句**的小项目。如果是一个正经要长期维护的项目，**强烈建议用情景 2**。

### 为什么不推荐直接在 main 上改

- A、B 同时在 main 上改，两个人都 push，**后推的那个一定会被拒绝**（non-fast-forward），这时候新手最容易干的事就是 `git push --force`——一 force，对方本地的提交就没了。
- 没有 PR 这个"停下来看一眼"的机会，一行坏代码直接进 main，所有人下次 pull 都跟着坏。

### 第一次怎么搭

跟情景 2 的"搭仓库"完全一样（owner 加协作者、朋友 clone）。区别只在于**平时怎么干活**。

### 平时怎么干：每次都先同步再动手

**这是这个情景的全部命门**：只要你每次开工前都把远端最新拉下来，冲突概率就小很多。

```bash
cd ~/projects/demo
git switch main
bash scripts/safe_sync.sh        # 必须跑！它会先检查你干不干净，再 fetch + rebase
# 然后改代码、提交、推
git add -A
git commit -m "..."
git push origin main
```

### push 被拒了怎么办（这个情景的高频场景）

如果你忘了先同步，直接 push，会看到：

```
! [rejected]        main -> main (non-fast-forward)
error: failed to push some refs to '...'
hint: Updates were rejected because the tip of your current branch is behind
```

**正确做法**（按顺序，**绝对不要加 --force**）：

```bash
git fetch origin
git status                    # 看清楚你领先/落后多少
git pull --rebase origin main # 把你本地的新提交接在远端最新后面
# 有冲突？照 conflict-resolution.md 解，解完 git add + git rebase --continue
git push origin main          # 正常推上去
```

`git pull --rebase` 会把你本地这几个提交"搬家"到远端最新提交之上。如果搬的时候发现同一段代码两个人都改了，才会出现冲突。

### 怎么"合并"

这个情景没有 PR，直接就是 main。但建议**至少做到**：
- 推完之后喊对方一句"我刚推了 main，你下次开工记得 pull"。
- 重要的改动还是单独开个小分支推上去，合并前让对方看一眼——等于"临时走一次情景 2"。

### 冲突了怎么办

照 conflict-resolution.md。**特别提醒**：这个情景下冲突几乎必然发生在 main 上，解决完**必须**真跑一遍代码再 push。

### 什么情况下不该用这个情景

- 超过 3 个人同时开发 → 切情景 2。
- 有发布节奏 / 要打版本 → 至少开 release 分支（情景 6 是打标签，不是分支策略）。
- 两个人不同时区、经常几天不同步 → 直接上情景 2，别硬撑。
- 看到 `! [rejected]` 你第一反应是想加 `--force` → 立刻停下来切情景 2，你不适合这个流程。

---

## 情景 6：打版本标签（给别人留一版）

**对应哪种大白话答案**："我想留个版本"/"发布一版给别人用"。

**什么时候用**：项目到了一个里程碑（v0.1、v1.0），想给它贴个名字，以后别人问"你给我那个能跑的版本是哪个 commit"，你一指 tag 就行。**就是打个记号，不改协作流程。**

### 怎么打 tag（三步走）

先确认你要发布的代码已经在 main 上、并且推上去了：

```bash
git switch main
bash scripts/safe_sync.sh
git log --oneline -5          # 确认 HEAD 就是你想发布的那个提交
```

然后打一个**带说明的附注标签**（annotated tag，推荐，比轻量标签多了作者、时间、说明）：

```bash
git tag -a v0.1 -m "v0.1: 第一个能用的版本，登录页跑通了"
git push origin v0.1          # 注意：普通 git push 不会把 tag 一起推上去，要单独推
```

一次推所有 tag：

```bash
git push origin --tags
```

### 怎么用这个 tag

- 在 GitHub 仓库页面，右边 "Releases" → "Draft a new release"，选刚才打的 tag，写 Release notes，发布。别人就能下载源码 / 看到这一版改了啥。
- 想回到某个版本的代码看看：

```bash
git checkout v0.1             # 进入 detached HEAD，只是看，不要在这上面改
# 看完了：git switch main
```

### 平时和 tag 的关系

tag 是**里程碑快照**，不是日常工作流。日常还是按情景 1~5 走，到了一个节点再回来打 tag。
**不要**为了"管理发布"去搞 Git Flow / 各种 release 分支——对两个人的小项目太重了。

### 什么情况下不该用这个情景

- 还在天天改、没有"这一版能用了"的感觉 → 先别打 tag。
- 你其实是想要"两个并行版本同时维护"（比如 v1 还在修 bug、v2 在开发）→ 那需要 release 分支，已经超出这个 Skill 的范围，建议直接升级到情景 2 + 自己研究 release branch。
- 打错了 tag（打错 commit 了）：还没 push 就 `git tag -d v0.1` 删了重打；已经 push 了就要 `git push origin :refs/tags/v0.1` 删掉远端再推——这一步算高风险，先和用户确认。

---

## 选错了怎么办

发现用错情景了（比如本来该用情景 2，结果用了情景 5 把 main 搞乱了），不要硬撑：
1. 立刻跑 `bash scripts/preflight.sh` 看现在状态；
2. 没推上去的本地改动，按 conflict-resolution.md 或 stash 保住；
3. 切到正确情景，从"第一次怎么搭"那一节的"接上远端"步骤继续，**不需要**把现有历史推倒重来。
