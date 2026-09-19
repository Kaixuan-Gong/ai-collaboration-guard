# 协作情景手册（7 套流程 + 2 个附录，对号入座）

这份手册和 SKILL.md 末尾的"情景速查"表一一对应。**先读那张大表判断你属于哪种，再翻到对应小节。**
不同情景的命令和节奏是真的不一样，别把情景 2 的命令换个名字套到情景 5 上。

## 关于脚本路径（重要）

本文里所有 `bash <skill>/scripts/...` 中的 `<skill>` 指**你本机这个 Skill 的安装根目录**。
举例：如果你把它装在 `~/.claude/skills/ai-collaboration-guard`，就写成：

```bash
bash ~/.claude/skills/ai-collaboration-guard/scripts/preflight.sh
bash ~/.claude/skills/ai-collaboration-guard/scripts/safe_sync.sh
```

**别**在你的项目目录里另放一个叫 `preflight.sh` / `safe_sync.sh` 的脚本然后跑它——那不是这个 Skill 的脚本，行为可能不一样。
这些是 bash 脚本：**Windows 需要 WSL 或 Git Bash 才能跑**；不同 AI 编程工具对"调用自定义脚本 / 路径"的支持本仓库未实测，请按你用的工具自己接一下。

## 关于 `git add` 的默认姿势

**别**复制 `git add -A` 或 `git add .` 当默认动作。正确节奏：

```bash
git status                 # 看改了哪些文件
git diff                   # 看具体改了啥（确认没把 .env、密钥、node_modules 纳进来）
git add path1 path2        # 只加你确定要提交的文件，一个一个列出来
git commit -m "说人话写干了啥"
```

全局 `.gitignore` 挡不住"你手滑 add 进来的东西"，所以按显式路径加是底线。

## 约定

- 下面所有命令里，`your-name`、`you@example.com`、`~/projects/demo`、`yourname/what-you-do` 都是占位符，换成你自己的。
- 分支名一律用"谁在做 + 做什么"，例如 `zhangkai/login-page`，别用 `test`、`wip`、`123`。
- 开工前先跑 `bash <skill>/scripts/preflight.sh`，脏了就先按它说的处理。

---

## 情景 1：单人起步备份（从零开始，还没朋友加入）

**对应哪种大白话答案**："还一行代码都没有、想从零开始" + "现在就我一个人先用 AI 写"。

**什么时候用**：你刚想到一个点子，自己先拿 AI 写着玩，想把代码放到网上备份、以后万一电脑坏了不丢。**这是最简单的起步流程**，等朋友要加入了再切到情景 2。

### 第一次怎么搭

```bash
# 1. 建项目目录（如果还没有）
mkdir -p ~/projects/demo
cd ~/projects/demo
git init -b main          # 默认主分支叫 main（老版本 git 用 git init 然后 git switch -c main）

# 2. 写个 .gitignore（第一次提交前一定要有，见 setup-checklist.md）
#    把 node_modules/、.env、venv/、__pycache__/、.DS_Store、dist/ 都挡上

# 3. 配置你的身份（仓库级，只影响这个项目；想全局配就去掉 --local）
git config --local user.name  "your-name"
git config --local user.email "you@example.com"

# 4. 第一次提交（按显式路径，别用 git add -A）
git status
git diff
git add README.md .gitignore
git commit -m "init: 项目起步"

# 5. 在 GitHub 网页上新建一个空仓库（不要勾 README、不要勾 .gitignore，避免和本地冲突），
#    然后照着 GitHub 页面上"…or push an existing repository from the command line"那一段：
git remote add origin git@github.com:your-name/demo.git
git push -u origin main
```

### 平时每天怎么同步 / 提交 / 推

单人项目其实没有"和别人同步"的问题，节奏就是**小步提交、经常备份**：

```bash
bash <skill>/scripts/preflight.sh
# 改完一段能跑的代码就：
git status
git diff
git add path1 path2
git commit -m "说人话写这次干了啥，例如: 加了登录页的表单校验"
git push origin main
```

**规则**：别攒一大堆改动一次 commit。每做完一个能跑的小功能就 commit 一次，出问题好回退。

### 怎么合并

单人项目没有"合并别人的活"这回事，不需要 PR。直接在 main 上提交就行。

### 冲突了怎么办

单人一般不会冲突。真出现了（比如你在两台电脑上都改了），照 conflict-resolution.md 处理。

### 什么情况下不该用这个情景

- 朋友要加入一起写了 → 切到情景 2 / 3 / 4 / 5。
- 你已经在别的地方有代码了 → 不要重新 init，走本文末尾的附录 A"把已有本地代码接进 GitHub"。
- 要给别人发布一版 / 打版本号 → 见情景 7。

---

## 情景 2：两台电脑 + 协作者（最常见的主流程）

**对应哪种大白话答案**："已经有代码了" + "各自用自己的电脑" + "朋友能直接往仓库写" + "每个人单独做一块、做完再合起来"。

**什么时候用**：你和朋友各自有电脑，你已经把他加成了 GitHub 仓库的协作者。这是**推荐的多人协作姿势**：每人开自己的分支，做完开 PR，另一个人看一眼再合。

### 第一次怎么搭（你是仓库 owner）

```bash
# 1. 你这边先有一个本地仓库（同情景 1 的前 5 步），main 分支已推到 GitHub。

# 2. 在 GitHub 网页上把朋友加成协作者（不需要 gh CLI）：
#    ① 打开 https://github.com/your-name/demo
#    ② 点上面那一排标签里的 "Settings"（在最右边）
#    ③ 左边菜单点 "Collaborators"（有的版本人叫 "Collaborators and teams"）
#    ④ 点 "Add people"，输入朋友的 GitHub 用户名，发邀请
#    ⑤ 朋友要去他自己的邮箱 / GitHub 通知里点接受邀请，加完才算数
```

> "能点开 GitHub 上那个仓库"不等于"有写权限"。要看 Settings → Collaborators 列表里有没有他，
> 或者让他真的试着推一次——这才是判断有没有写权限的硬标准。

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

**开工前先确认主线叫什么，再从最新主线开新分支**（不要从一个不知道是什么的本地分支上分叉）：

```bash
cd ~/projects/demo
bash <skill>/scripts/preflight.sh

# ① 先把远端最新 fetch 下来
git fetch origin

# ② 确认主线叫什么（默认 main；有些老项目叫 master）
git symbolic-ref refs/remotes/origin/HEAD   # 会打印 refs/remotes/origin/main
git switch main                              # 切到主线（如果不是 main，换成实际的）

# ③ 把主线快进到最新
git merge --ff-only origin/main

# ④ 从最新主线开新分支
git switch -c friend-name/what-you-do
# 例如：git switch -c zhangkai/login-page
```

**改完一段就提交、推分支**：

```bash
git status
git diff
git add path1 path2
git commit -m "login: 加了手机号输入框和校验"
git push -u origin friend-name/what-you-do
```

`-u` 第一次写，以后直接 `git push` 就行。

### 怎么合并（开 PR，不是本地直接合）

1. 推完分支后，GitHub 仓库首页会跳出一行黄色提示 "*friend-name/what-you-do had recent pushes*"，右边一个 "Compare & pull request" 按钮，点它。
2. 填个标题和说明：这次改了什么、为什么。点 "Create pull request"。
3. **合并前先把最新主线合进这个功能分支**（不要 rebase 已经推上去的提交）：

   ```bash
   git fetch origin
   git switch friend-name/what-you-do
   git merge origin/main        # 普通 merge，不动已经推过的提交
   # 有冲突？照 conflict-resolution.md 解
   git push origin friend-name/what-you-do
   ```

   这样 PR 上的代码就是"功能分支 + 最新主线"的结果，不会和主线合不上。
4. **喊另一个人来看一眼**：不是合 PR 的人自己点 merge。对方在 PR 页面：
   - 先去 "Files changed" 标签看 diff；
   - 能跑的话最好把分支拉到本地跑一下（`git fetch origin` + `git switch friend-name/what-you-do`）；
   - 没问题就回 "Conversation" 标签点 "Review changes" → "Approve"。
5. 点 "Merge pull request" → "Confirm merge"。合完后分支就可以删了。

### 关于分支保护 / 必审 / CI（如实说，别美化）

- **分支保护规则**（禁止直接推主线、要求 PR、要求必过检查）：只有仓库 **owner** 能在 GitHub 网页
  `Settings → Branches → Branch protection rules` 里设置（也可以用 CLI / API 设，但要回到这个页面**回读一遍**确认规则真的生效了）。
  免费账号的公开仓库**可以**用基本的分支保护，但"要求 reviewer 批准""要求 status checks 通过"在某些私有仓库 / 套餐上才有。
  先去设置页看得到什么，就说什么。**看不到的功能不要假装有。**
- **PR 互相 review**：真实两个 GitHub 账号时，互相 review 是有意义的。**同一个账号给自己 PR 点 approve 不算真审查**——
  可以用来走流程，但要告诉用户"这是你自己审自己，对方最好也点进来看看"。另外：**新 push 一个 commit 会让旧的 approve 失效**，
  不要指望上次点过的 approve 一直有效。
- **CI 自动检查**：如果加了 GitHub Actions，**必须确认它真的会跑、真的会变绿**：
  - 不要写一个 `paths: [ 'src/only-changed-by-nobody/' ]` 这种永远不触发的过滤，否则 PR 永远卡在 pending。
  - 不要把"要求必过"套在一个根本跑不起来的 workflow 上，那样谁都合不进去。
  - 合并前真的去 PR 页面看一眼检查状态：绿了再合，红了就看日志修，别靠"应该没事"。
  - 套餐 / 免费版没有的能力，就如实告诉用户："这部分目前没有自动检查，合并前你自己跑一下 / 看一眼。"

### 冲突了怎么办

PR 页面如果显示 "This branch has conflicts"，或者你本地 merge 时炸了，照 conflict-resolution.md 处理。
**不要**在 PR 页面一键 "Resolve conflicts" 完事就合——合完一定要真的跑一下代码。

### 什么情况下不该用这个情景

- 朋友点绿色 Code 按钮发现根本推不回去（没写权限）→ 切到情景 5（fork）。
- 两个人其实是轮流用同一台电脑 → 切到情景 3。
- 两个人 / 两个 AI 想**同时**在一台机器上并行干活 → 切到情景 4（worktree）。
- 项目很小、就俩人互相信任、嫌 PR 麻烦 → 看情景 6，但先读它开头的风险说明。
- 你自己一个人玩、还没人加入 → 情景 1 更简单。

---

## 情景 3：同一台电脑，两人轮流用

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
bash <skill>/scripts/preflight.sh
```

看到工作区干净 → 直接换下一个人用。
看到还有没提交 / 未跟踪文件 → **二选一，别留着过夜**：

```bash
# 选 A：把手上的活存个档，下次接着干
git status && git diff
git add path1 path2
git commit -m "wip: 还没写完的一半"

# 选 B：先收起来，别提交半成品（带个明确的名字，别用默认 stash）
git stash push -m "your-name WIP: 登录页还没写完"
# 有新文件要一起收？才加 -u：git stash push -u -m "..."
# 下次回来：git stash list 找到你那条，
#           git stash show -p stash@{n} 看一眼内容确认是自己的活，
#           再 git stash pop stash@{n}
# （别光 git stash pop——默认弹最新一条，可能弹到别人的活）
```

**然后才换身份**：

```bash
git config --local user.name  "下一个人的名字"
git config --local user.email "下一个人的邮箱"
bash <skill>/scripts/safe_sync.sh    # 换人后先同步一下远端
```

### 怎么合并

跟情景 2 一样：各自开 `yourname/what-you-do` 分支，开 PR，互相 review。
**别因为在同一台电脑上就图省事直接 push 到 main**——本地分支看起来是连着的，但 GitHub 上的历史还是乱。

### 冲突了怎么办

照 conflict-resolution.md。同机协作最常见的冲突原因就是"换人前没 stash / commit，两个人的改动叠在工作区里"——养成换人前跑 preflight 的习惯，能躲开大部分坑。

### 什么情况下不该用这个情景

- 其实是两台电脑远程协作 → 情景 2。
- 两个人想**同时**（不是轮流）在一台机器上干活 → 情景 4（worktree）。

---

## 情景 4：同一台电脑，两个人 / 两个 AI **并行**干活（git worktree）

**对应哪种大白话答案**："我和朋友（或我和我自己的另一个 AI）想同时在这台电脑上各干各的，但用的是同一个项目"。

**和情景 3 的区别**：情景 3 是**轮流**（一个人用完另一个人再用），这个情景是**并行**——你一个人开两个终端，每个终端干一件不同的事，或者你和朋友远程连到同一台机器同时干活。

**核心思路**：用 `git worktree` 给每个任务开一个**独立的工作目录**，共享同一个 `.git`，但代码文件互不干扰。

### 怎么开一个并行工作目录

```bash
cd ~/projects/demo                  # 这是主工作目录
git fetch origin
git switch main
git merge --ff-only origin/main    # 先把主工作目录的主线更新到最新

# 给新任务开一个并行工作目录（名字随便起，放在项目外面更清楚）
git worktree add ../demo-feature-login -b yourname/login-page
# 上面这行做了两件事：
#   ① 新建分支 yourname/login-page
#   ② 在 ../demo-feature-login 里 checkout 出这个分支

# 进去开干
cd ../demo-feature-login
```

开了几个 worktree 就能同时干几件事：

```bash
git worktree list
# 会列出所有工作目录和它们各自在哪个分支上
```

### 身份：改 git 身份 ≠ 换 GitHub 账号

- 主工作目录和 worktree **共享同一份 `config`**，所以 `user.name` / `user.email` 也共享。
- 如果你在一台机器上用两个不同 GitHub 身份，**光改 git 身份不够**：
  - SSH key / 凭证也得各管各的（用 ~/.ssh/config 给不同 host 配不同 key，或用 SSH 协议带 host 别名）。
  - 改 `user.name` / `user.email` 只影响 commit 署名；push 用的是 SSH key / credential，**不会跟着变**。
- 最简单的做法：一台机器就用一个 GitHub 账号跑，需要另一个账号时干脆**另 clone 一份**到不同目录，别混在 worktree 里。

### worktree 不共享的东西（你得自己隔离）

worktree 只隔离**代码文件**。下面这些**不会**自动隔离，你得自己想办法：

- **本地数据库 / SQLite 文件**：每个 worktree 指向不同的 DB 文件，或者用不同的端口起服务。
- **端口**：两个 worktree 同时跑 dev server，别都占 3000，一个 3000 一个 3001。
- **构建产物 / node_modules**：worktree 里 `npm install` 出来的 `node_modules` 是各自独立的（因为不在 git 里），这是好事；但磁盘占用会翻倍，心里有数。
- **环境变量 / .env**：每个 worktree 自己放一份，别共用。

### 规矩：别在别人正活跃的 worktree 里切他的分支

`git worktree list` 看一眼哪个目录在哪个分支上。**A 在 `../demo-feature-login` 里改 `yourname/login-page` 时，你不要进那个目录去 `git switch` 到别的分支**——会把 A 的未提交改动带得满处跑。

你要干自己的活，就**自己开一个新 worktree**。

### 平时怎么提交 / 推

和情景 2 一样，只是 `cd` 到你那个 worktree 目录里操作：

```bash
cd ../demo-feature-login
git status
git diff
git add path1 path2
git commit -m "..."
git push -u origin yourname/login-page
```

合并：开 PR，和情景 2 一模一样。

### 什么情况下不该用这个情景

- 你只是想试一下老版本代码、看一眼历史——那用 `git switch --detach <tag>` 到主工作目录就行，不必 worktree。
- 你和朋友其实各自有电脑 → 情景 2 更简单。
- 你只想一个人轮流干两件事 → 情景 3 或干脆别并行。

---

## 情景 5：朋友没有写权限（fork + PR）

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

# 关键：把"原作者的仓库"加为 upstream，不然没法同步他的更新
git remote add upstream git@github.com:your-name/demo.git
git remote -v
# 应该看到：
#   origin    git@github.com:friend-name/demo.git     （你自己的 fork）
#   upstream  git@github.com:your-name/demo.git      （原作者的仓库）
```

### 平时怎么干（朋友侧）

每次开工前**先同步原仓库的最新 main**（这是 fork 工作流最容易忘的一步）：

```bash
git fetch upstream
git switch main
git merge --ff-only upstream/main     # 默认快进；本地 main 上没有自己的提交时这是安全的
# 万一你在自己 main 上也有提交（不推荐），ff-only 会失败，
# 那时再考虑 git merge upstream/main，但要想清楚——fork 的 main 应该永远跟原仓库走。
```

然后开新功能分支干活：

```bash
git switch -c friend-name/what-you-do
```

改完推到**自己的 fork**（不是原仓库）：

```bash
git status && git diff
git add path1 path2
git commit -m "..."
git push origin friend-name/what-you-do
# origin 在这里 = 朋友自己的 fork，不是原仓库
```

### 怎么合并

1. 朋友在自己 fork 的 GitHub 页面上，会看到 "Compare & pull request" 按钮——**注意方向**：
   base repository 要选 `your-name/demo` 的 `main`，head repository 是 `friend-name/demo` 的 `friend-name/what-you-do`。
2. 你（原作者）去 `your-name/demo` 的 Pull requests 标签页，就能看到这个 PR。review、讨论、合并，跟情景 2 一样。

### 朋友怎么持续同步原仓库的更新（标准三步）

```bash
git fetch upstream                 # ① 把原仓库最新信息拉下来
git switch main                    # ② 切回自己的 main
git merge --ff-only upstream/main   # ③ 把 main 快进到原仓库最新（默认 ff-only）
git push origin main               # 顺手把自己 fork 的 main 也更新（可选，但推荐）
```

以后再开新功能分支，就从最新的 main 开，不会和原仓库差太远。

### 冲突了怎么办

照 conflict-resolution.md。fork 工作流里冲突最常见的原因就是"忘了上面这三步，自己的 main 落后原仓库一两个月"。

### 什么情况下不该用这个情景

- 你和朋友关系很铁、也信得过 → 直接走情景 2 把他加成协作者，省掉 fork 这一层。
- 你是单人项目、根本没人给你发 PR → 用情景 1。

---

## 情景 6：直接在主分支上改（先讲清楚风险）

**对应哪种大白话答案**："小项目、互相信任，想大家都直接在同一条主线上改"。

**先把风险说在前面**：这是所有流程里最容易"互相干扰"的一种。它适合**两个人都经常在线、改动都很小、出了问题能很快看到**的小项目。如果是一个要长期维护的项目，**强烈建议用情景 2**。

### 为什么不推荐直接在 main 上改

- A、B 同时在 main 上改，两个人都 push，**后推的那个会被 Git 拒绝**（non-fast-forward）——这是 Git 在保护远端历史，**不会**把对方已经在本地的提交删掉，只是这次 push 没上去。但新手一看到 `! [rejected]` 就加 `--force`，那才会真的把远端历史盖掉。
- 没有 PR 这个"停下来看一眼"的机会，一行坏代码直接进 main，所有人下次同步都跟着坏。

### 第一次怎么搭

跟情景 2 的"搭仓库"完全一样（owner 加协作者、朋友 clone）。区别只在于**平时怎么干活**。

### 平时怎么干：每次都先同步再动手

**这是这个情景的全部命门**：只要你每次开工前都把远端最新拉下来，冲突概率就小很多。

```bash
cd ~/projects/demo
git switch main
bash <skill>/scripts/safe_sync.sh        # 必须跑！它会先检查你干不干净，再 fetch + ff-only
# 然后改代码、提交、推
git status && git diff
git add path1 path2
git commit -m "..."
git push origin main
```

### push 被拒了怎么办（这个情景的高频场景）

如果你忘了先同步，直接 push，会看到：

```
! [rejected]        main -> main (non-fast-forward)
error: failed to push some refs to '...'
hint: Updates were rejected because the remote contains work that you do not
hint: have locally. This is usually caused by another repository pushing to
```

**正确做法**（按顺序，**绝对不要加 --force**）：

```bash
git fetch origin
git status                    # 看清楚你领先/落后多少
# 如果你本地没新提交：
git merge --ff-only origin/main
# 如果你本地也有新提交（分叉了）：二选一，想清楚再动手
#   A) 普通合并（共享分支推荐）： git merge --no-rebase origin/main
#   B) 只在没人基于这个分支干活时才 rebase： git rebase origin/main
# 有冲突？照 conflict-resolution.md 解
git push origin main          # 正常推上去
```

`--force` 只在"分支只有你一个人在用、你刚推过、没人基于它干活"且你已向协作者说清楚之后才考虑，而且用 `--force-with-lease` 而不是 `--force`。

### 怎么"合并"

这个情景没有 PR，直接就是 main。但建议**至少做到**：
- 推完之后在群里 / 聊天里说一声"我刚推了 main，你下次开工记得同步"。
- 重要的改动还是单独开个小分支推上去，合并前让对方看一眼——等于"临时走一次情景 2"。

### 冲突了怎么办

照 conflict-resolution.md。**特别提醒**：这个情景下冲突几乎必然发生在 main 上，解决完**必须**真跑一遍代码再 push。

### 什么情况下不该用这个情景

- 超过 3 个人同时开发 → 切情景 2。
- 两个人不同时区、经常几天不同步 → 直接上情景 2，别硬撑。
- 看到 `! [rejected]` 你第一反应是想加 `--force` → 停下来切情景 2。

---

## 情景 7：打版本标签（给别人留一版）

**对应哪种大白话答案**："我想留个版本"/"发布一版给别人用"。

**什么时候用**：项目到了一个里程碑（v0.1、v1.0），想给它贴个名字，以后别人问"你给我那个能跑的版本是哪个 commit"，你一指 tag 就行。**就是打个记号，不改协作流程。**

### 打 tag 之前先验证

```bash
git switch main
bash <skill>/scripts/safe_sync.sh
git log --oneline -5          # 确认 HEAD 就是你想发布的那个提交
```

如果 main 上设了分支保护 / 必过 CI，**去 PR 页面或 Actions 页面确认这个 commit 真的是绿的、真的在受保护的主线上**。别 tag 一个没人验证过的提交。

### 怎么打 tag（三步走）

```bash
# 打一个带说明的附注标签（annotated tag，推荐）
git tag -a v0.1 -m "v0.1: 第一个能用的版本，登录页跑通了"

# 只推这一个 tag（不要 git push --tags，那会把你本地所有 tag 都推上去，包括打错的）
git push origin v0.1
```

### 怎么用这个 tag

- 在 GitHub 仓库页面，右边 "Releases" → "Draft a new release"，选刚才打的 tag，写 Release notes，发布。别人就能下载源码 / 看到这一版改了啥。
- 想回到某个版本的代码看看：

```bash
git switch --detach v0.1      # 进入 detached HEAD，只是看，不要在这上面改
# 看完了：git switch main
```

### 打错了 tag 怎么办

- **还没 push**：`git tag -d v0.1` 删了重打。
- **已经 push 了**：**优先**打一个新的补丁 tag（比如 v0.1.1），不要去删远端 tag 重打——删远端 tag 会影响所有已经基于它工作的人。
- 实在必须删远端 tag（比如 tag 指向了错误的提交且还没人用）：`git push origin :refs/tags/v0.1`，这一步是高风险操作，先和协作者说清楚。

### 平时和 tag 的关系

tag 是**里程碑快照**，不是日常工作流。日常还是按情景 1~6 走，到了一个节点再回来打 tag。
**不要**为了"管理发布"去搞 Git Flow 那种重型分支模型——对两个人的小项目太重了。

---

## 附录 A：把已有本地代码接进 GitHub（或把已有远端接到新机器）

**场景**：你电脑上已经有一堆代码，还没推到 GitHub；或者 GitHub 上已经有了，你新换了台电脑想接着写。**别**重新 init / 别 force push / 别 reset --hard，按下面接。

### A.1 本地有代码、GitHub 上还没有

```bash
cd ~/projects/demo
git init -b main
# .gitignore 先写好
git config --local user.name  "your-name"
git config --local user.email "you@example.com"

# 按显式路径把该提交的都提交（别 git add -A）
git status
git diff
git add path1 path2 ...
git commit -m "init: 本地已有代码首次提交"

# 在 GitHub 网页新建**空**仓库（不要勾 README / .gitignore / license），然后：
git remote add origin git@github.com:your-name/demo.git
git push -u origin main
```

### A.2 GitHub 上已经有了，本地是新机器

直接 clone，别重新 init：

```bash
git clone git@github.com:your-name/demo.git
cd demo
git config --local user.name  "your-name"
git config --local user.email "you@example.com"
```

### A.3 两边都已经有历史（本地一份、GitHub 一份，都已经提交过）

这是最容易出事的。**先备份，再看清两边历史，再 merge。**

```bash
# ① 备份本地当前状态（保险）
cp -r ~/projects/demo ~/projects/demo.backup-$(date +%Y%m%d)

# ② 本地初始化或接 remote
cd ~/projects/demo
git init -b main                       # 如果还没 init
git remote add origin git@github.com:your-name/demo.git

# ③ 先 fetch 远端，不要急着 pull
git fetch origin

# ④ 看看两边历史长什么样（关键！）
git log --oneline main                 # 你本地的
git log --oneline origin/main          # 远端的

# ⑤ 把本地的 commit 先 commit 干净（如果工作区脏了）
git status
# ... 按显式路径 add + commit，或 stash

# ⑥ 用 merge 把远端合进来（不要 --force、不要 reset --hard、不要重新 clone）
git merge origin/main
# 有冲突？照 conflict-resolution.md 解
# 解决完真跑一遍代码再推

# ⑦ 推上去
git push -u origin main
```

**绝对不要**的做法：
- `git push --force`：会把远端别人的历史盖掉。
- `git reset --hard origin/main`：会把你本地还没推的提交丢了。
- 重新 clone 然后把旧代码拷过去：Git 历史就断了，以后再也合不回来。

---

## 附录 B：hotfix / 旧版维护（可选）

如果你已经发布了 v1.0，现在 main 在开发 v2.0，线上 v1.0 有个紧急 bug 要修：

### 做法一：cherry-pick（只需要 backport 一两个 commit）

```bash
# 在 main 上把 bug 修好，正常 PR 合进去
# 假设修好的 commit 是 abc1234

# 切到旧版 tag，开个 hotfix 分支
git switch --detach v1.0
git switch -c hotfix/v1.0.1

# 把 main 上那个修复 commit 摘过来
git cherry-pick abc1234
# 有冲突？照 conflict-resolution.md

# 跑测试、推、开 PR 合到一个 release 分支（见做法二），或直接打补丁 tag
git push -u origin hotfix/v1.0.1
```

### 做法二：release 分支（需要长期维护旧版）

```bash
# 从 v1.0 tag 开一个 release 分支
git switch --detach v1.0
git switch -c release/1.x

# hotfix 都在 release/1.x 上做
# 修完打补丁 tag
git tag -a v1.0.1 -m "v1.0.1: 修复 XXX 紧急 bug"
git push origin v1.0.1
```

这两个做法都比"在 main 上打补丁然后假装线上也是 main"靠谱。**别**为了省事直接改 main 然后 force 到旧版——历史会乱。

---

## 选错了怎么办

发现用错情景了，不要硬撑：
1. 立刻跑 `bash <skill>/scripts/preflight.sh` 看现在状态；
2. 没推上去的本地改动，按 conflict-resolution.md 或 stash 保住；
3. 切到正确情景，从"接上远端"那一步继续，**不需要**把现有历史推倒重来。
