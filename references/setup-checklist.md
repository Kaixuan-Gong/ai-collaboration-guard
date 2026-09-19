# 前置环境检查清单

照着这份清单一项项过。哪一步卡住，就单独跑那一行看报什么错。
**不要假设用户已经配好了**——新手最常见的卡点就是"以为配过了，其实没有"。

---

## 1. git 装了没

```bash
git --version
```

应该打印类似 `git version 2.39.0`。
- 没装的话：
  - **macOS**：直接在终端跑 `git --version`，如果系统没装，会弹窗提示装 "Command Line Developer Tools"，点"安装"等它装完。
  - **Windows**：去 https://git-scm.com/download/win 下载安装包，一路下一步。
  - **Linux**：`sudo apt install git` 或 `sudo dnf install git`。

## 2. 配 git 身份（提交会署什么名）

```bash
git config --global user.name  "your-name"
git config --global user.email "you@example.com"
```

**--global 和 --local 的区别**：

- `--global`（上面这条）：这台电脑上**所有**仓库都用这个身份。一个人一台机器，用 global 就行。
- `--local`：只影响**当前这一个仓库**。**同一台电脑多人轮流用**（情景 3）时，每个仓库单独配 local，不要配 global。

确认配好了：

```bash
git config user.name
git config user.email
```

两行都应该打印出你刚填的东西。**不要**把真实邮箱、本机用户名写进这个 Skill 的任何示例。

## 3. 配 SSH 密钥（让你电脑能免密推到 GitHub）

GitHub 现在推荐用 SSH（或者它的 HTTPS 自带凭据）。下面是 SSH 这套：

### 3.1 生成密钥

```bash
ssh-keygen -t ed25519 -C "you@example.com"
```

一路回车（存到默认位置 `~/.ssh/id_ed25519`，passphrase 可以空着，也可以设一个但每次推要输）。

如果你电脑很老不支持 ed25519，用：

```bash
ssh-keygen -t rsa -b 4096 -C "you@example.com"
```

### 3.2 把公钥贴到 GitHub

**公钥**是 `~/.ssh/id_ed25519.pub`（注意末尾有 `.pub`），**私钥** `~/.ssh/id_ed25519` 没有 `.pub`，那个绝对不能给别人看。

打印公钥内容：

```bash
cat ~/.ssh/id_ed25519.pub
```

会看到一行以 `ssh-ed25519 AAAA....` 开头、末尾是你邮箱的字符串。**整行复制**。

然后在 GitHub 网页：
1. 右上角你的头像 → "Settings"。
2. 左边菜单点 "SSH and GPG keys"。
3. 绿色按钮 "New SSH key"。
4. Title 随便写（比如 "我的 MacBook"），Key 那一栏粘贴刚才复制的那一行。
5. 点 "Add SSH key"。

### 3.3 验证 SSH 通了

```bash
ssh -T git@github.com
```

第一次会问 `Are you sure you want to continue connecting (yes/no)?`，输 `yes` 回车。
成功的话会看到类似：

```
Hi your-name! You've successfully authenticated, but GitHub does not provide shell access.
```

看到 `Hi <你的用户名>` 就说明通了。如果报 `Permission denied (publickey)`，多半是公钥没贴对、或者贴成了私钥。

## 4. 默认分支名用 main

新仓库统一用 `main`（不要再用老习惯的 `master`）。初始化时：

```bash
git init -b main
```

老版本 git（< 2.28）不支持 `-b`，就：

```bash
git init
git checkout -b main
```

GitHub 网页上新建仓库时，默认分支名也选 `main`。两边对齐，不然 push 上去会推成 `master` 又得改。

## 5. .gitignore 该挡什么

**第一次 commit 之前**先在项目根目录建 `.gitignore`，至少包含：

```gitignore
# 环境变量 / 密钥（绝对不能提交）
.env
.env.*
!.env.example
*.pem
*.key
*.p12
secrets.json
id_rsa*

# 依赖目录
node_modules/
venv/
.env/
__pycache__/
*.pyc

# 构建产物
dist/
build/
out/

# 系统 / 编辑器杂物
.DS_Store
Thumbs.db
.idea/
.vscode/
```

**已经误把密钥提交进去了怎么办？** 光删文件再 commit 不够——历史里还留着。最稳的办法是**先去对应平台把那个密钥作废 / 换一个新的**，然后再清理历史。清理历史是高风险操作，照 safety-rules.md 第四节走。

## 6. 最终自检（跑一遍这几条就算齐活）

```bash
git --version                                  # ① git 装好了
git config user.name && git config user.email   # ② 身份配了
ssh -T git@github.com                           # ③ SSH 通了
```

都通过，就可以开始用 SKILL.md 里的流程了。

---

## 关于 gh CLI（可选，不是必须）

GitHub 官方有个命令行工具 `gh`，能在终端里直接建仓库、加协作者、开 PR，省得开网页。**它不是必需的**，本 Skill 所有流程都不依赖它。
想装可以装，但别让用户为了跟着这份手册走而额外装它。
