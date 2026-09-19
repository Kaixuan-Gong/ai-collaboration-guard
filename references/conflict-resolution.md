# 冲突怎么处理

push 被拒、pull / merge / rebase 时炸了，先别慌。冲突**不是 bug**，是 Git 在告诉你："这两处不一样，我不敢替你选哪个对。"
你的工作区文件没丢，只是被 Git 用标记符圈出来了，等你（或你的 AI）做决定。

## 第一步：现在到底是什么状态

先跑：

```bash
git status
```

看输出里有没有这几种字：

- `You have unmerged paths.` / `Unmerged paths:` —— 正在 merge 或 pull 过程中冲突了。
- `interactive rebase in progress` —— 正在 rebase 过程中冲突了。
- `Both modified:` / `both modified:` —— 具体哪些文件冲突了。

**别同时跑两个冲突流程**（边 merge 又边 rebase）。先决定是"继续解决"还是"退出重来"。

## 想直接退出，回到同步前的样子

随时可以安全退出，你的本地工作不会丢：

```bash
# 如果正在 merge / pull 中间：
git merge --abort

# 如果正在 rebase 中间：
git rebase --abort

# 如果正在 cherry-pick 中间：
git cherry-pick --abort
```

跑完再 `git status`，就回到冲突前的干净状态了。**搞不清楚就先 abort**，没什么丢人的。

## 第二步：读懂冲突标记

打开任何一个 `both modified` 的文件，你会看到这种块：

```
function login(username, password) {
<<<<<<< HEAD
  // 我这边写的
  if (!username) throw new Error("没填用户名");
=======
  // 朋友那边写的
  if (username === "") throw "空的";
>>>>>>> friend-name/login-page
  return api.post("/login", { username, password });
}
```

读法：

- `<<<<<<< HEAD` 到 `=======` 之间：**你这边**的版本。
- `=======` 到 `>>>>>>> <分支名>` 之间：**对方分支**的版本。
- 前后没有标记的部分：两边一样，不用动。
- 那个分支名（`friend-name/login-page`）能告诉你这是从哪个分支 / 哪个提交来的——看不懂的地方去问问朋友他当时为啥这么写。

## 第三步：做决定，不要无脑 ours / theirs

新手容易犯的错：看到冲突就跑一句 `git checkout --ours <文件>` 或 `--theirs <文件>`，**整个文件选一边**。
很多时候这是错的——一个文件里可能既有你要保留的部分、也有朋友要保留的部分，直接选一边就把另一边的活丢了。

正确做法：

1. 打开文件，看每一块 `<<<<<<< ... ======= ... >>>>>>>`。
2. **想清楚哪一版是对的**——多半答案是"两边的逻辑合起来"，而不是二选一。例如上面那段，合并完应该是：

   ```js
   function login(username, password) {
     if (!username) throw new Error("没填用户名");
     return api.post("/login", { username, password });
   }
   ```

3. 删掉三个标记行（`<<<<<<<`、`=======`、`>>>>>>>`），把文件改成你想要的最终样子。

**只有**当你确定"这整个文件我这边对、对方那版完全不要"时，才允许用：

```bash
git checkout --ours   path/to/file   # 用你这边的整个文件
# 或
git checkout --theirs path/to/file   # 用对方整个文件
```

用之前先 `git diff path/to/file` 看一眼两边到底差了什么，别盲选。

## 第四步：告诉 Git 你改完了

```bash
git add path/to/resolved-file1 path/to/resolved-file2
```

**一个文件一个文件地加**，不要用 `git add -A`——冲突解决过程中工作区可能还有你不想一起提交的东西（比如本地调试改的 `.env`、临时日志），`-A` 会一起带走。
加之前先 `git status` 看一眼哪些是真的冲突解决完的、哪些是别的无关改动。

**注意**：`git add` 不是"提交"，是"我解决了，标记一下"。

然后：

- **如果在 merge / pull 中间**：直接 `git commit`（Git 会自动给你填一个 merge commit 的信息，能改就改，改人话点）。
- **如果在 rebase 中间**：`git rebase --continue`。它会接着把下一个提交 replay 上去，可能还有下一处冲突，重复第二~四步。

## 第五步（最容易被跳过）：跑代码 / 跑测试

**合并成功 ≠ 代码是对的。** Git 只能保证"文字层面不打架了"，它不知道这两段合起来能不能跑、逻辑对不对。

做完上面任何一步，**必须**：

1. 把项目启动起来 / 跑一下主要功能；
2. 如果有测试：`npm test` / `pytest` / 项目里任何跑测试的命令，**真的跑一遍**；
3. 看一眼改动的文件，确认没有残留 `<<<<<<<`、`=======`、`>>>>>>>`（可以 `grep -rn '^<<<<<<<\|^>>>>>>>' .` 扫一遍）。

逻辑层面的对错，**靠 review + tests，不靠合并动作本身**。
"合并按钮点下去是绿的"和"代码是对的"是两回事。

## 常见踩坑

- **合完发现跑不起来，想退回去**：刚合完还没 push 时，`git reset --hard ORIG_HEAD` 可以回到合并前（**但会丢掉你刚才解决冲突的工作**）。保险做法：先 `git stash push -m "your-name WIP: 合错了想退回"` 把当前状态存一份（有新文件要存才加 `-u`），再 reset。已经 push 了就别 reset，再提一个 commit 把问题修了。
- **冲突的文件你根本看不懂**（朋友刚改过的核心业务逻辑、你不熟的语言）→ **停下来问朋友 / 问用户**，别自己瞎猜着合。这是 safety-rules.md 第七条明确写的"该停的时候"。
- **一堆文件冲突**：先 `git status` 看清单，挑出来你知道的改，不知道的标出来问。不要"全选 ours"一把梭。
- **IDE 自动帮你合并了**：别信 IDE 给的合并结果，照样打开文件看一眼标记、跑一遍测试。
