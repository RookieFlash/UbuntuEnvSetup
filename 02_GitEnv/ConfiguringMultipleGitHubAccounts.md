
# 多个账号的Github配置

针对同时使用两个(或多个)GitHub 账号的场景,完整覆盖:密钥生成、`~/.ssh/config` 配置、仓库级身份、以及提交失败时的排查方法。


--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

## 1. 核心原理:提交身份与认证是两回事

多账号配置容易乱,是因为把两件事混在一起了:

| | 提交身份 | 认证 |
| --- | --- | --- |
| 配置项 | `user.name` / `user.email` | SSH 密钥 |
| 作用 | 决定提交记录上显示的署名 | 决定"以哪个账号的身份操作 GitHub" |
| 影响范围 | 只影响显示,不影响权限 | 决定能不能推送某个仓库 |
| 多账号做法 | 每个仓库单独设置(见 3.7 节) | 每个账号一把独立密钥(见 3 节) |

由此得出多账号配置的三个组成部分:**仓库级身份 + 每账号独立密钥 + SSH 别名路由**。

## 2. 配置前盘点:确认两边账号的真实信息

开始配置前,先确认三件事:

1. **两个账号的真实登录名**。
	以 GitHub 自己的输出为准:浏览器登录后点右上角头像,菜单里显示的名字就是登录名;
	`ssh -T` 成功后 `Hi` 后面的名字也是。**注册时以为的用户名和真实登录名可能不一致**(实战案例中曾把账号记成 `username02_2022`,实际登录名是 `username02`)。
2. **现有密钥盘点**,避免后面生成时覆盖:

```bash
ls -l ~/.ssh/
```

   已有 `id_ed25519` 的话,用 `ssh -T git@github.com` 验证它属于哪个账号(`Hi` 后面的名字)。

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

## 3. 生成独立密钥

```bash
ssh-keygen -t ed25519 -C "新账号的邮箱" -f ~/.ssh/id_ed25519_username01
ssh-keygen -t ed25519 -C "新账号的邮箱" -f ~/.ssh/id_ed25519_username02
# -f 指定独立文件名;不要用默认名,以免覆盖旧账号的 id_ed25519
```

生成两个文件:私钥 `id_ed25519_username01`(自己保留,不外传)、公钥 `id_ed25519_username01.pub`(上传给 GitHub)。查看公钥:

```bash
cat ~/.ssh/id_ed25519_username01.pub
```

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

## 4. 把公钥添加到对应账号
1. 登录**新账号**,打开 <https://github.com/settings/keys>
2. New SSH key → Title 随意(如"我的 Linux 电脑")→ 粘贴公钥 → Add SSH key

> 最容易踩的坑:**公钥加到了哪个账号,这把密钥就代表哪个账号**。
> 给新账号配的密钥却粘贴到了旧账号的 settings 里,是排查时最常见的错误。

### 4.1 配置 ~/.ssh/config:别名路由

编辑(或新建)`~/.ssh/config`,完整示例:

```text
# 账号一(默认):走 username01
Host username01		/* 这里的 github.com 可以改成 github 账号名，便于区分 */
  HostName github.com
  User git
  IdentityFile ~/.ssh/id_ed25519_username01	/* 这里改为对应账号的key文件名 */

# 账号二(本技术文章账号):走别名 username02
Host username02
  HostName github.com
  User git
  IdentityFile ~/.ssh/id_ed25519_username02
```

四个字段逐个说明:

| 字段 | 说明 | 能否改 |
| --- | --- | --- |
| `Host` | **本地别名**,只在本机使用。可自由命名,包括直接用账号名(如 `Host username02`);但不能是真实域名(尤其不能两个账号都写 `Host github.com`),不能重复 | 可自定 |
| `HostName` | 真实连接地址,固定为 `github.com` | 不能改 |
| `User` | GitHub SSH 服务的固定登录名,**永远是 `git`**,不要改成你的账号名(账号身份由密钥决定,不由登录名决定) | 不能改 |
| `IdentityFile` | 指向该别名要用的密钥文件,决定以哪个账号认证;用绝对路径(如 `/home/user/.ssh/id_ed25519_username02`)更保险 | 指向对应账号的密钥 |

原理:git 地址写 `git@username02:用户名/仓库.git` 时,SSH 按 `Host` 别名 `username02` 匹配这一段落,实际仍连接 github.com,但使用该段落指定的密钥认证。

补充说明:

- 别名的**三处一致**:`~/.ssh/config` 里的 `Host`、仓库 remote 地址里的主机部分、`ssh -T git@别名` 测试,必须完全一致;
- 不配别名的连接走默认规则:主机名 `github.com` 没有匹配段落时,SSH 尝试默认密钥 `~/.ssh/id_ed25519_username01`,所以"账号一"也可以不显式配置;
- 文件权限:若 ssh 报 `Bad owner or permissions on ~/.ssh/config`,执行 `chmod 600 ~/.ssh/config`。

### 4.2 验证:两条 ssh -T 各归各位

```bash
ssh -T git@username01     # 预期:Hi 账号一登录名!
ssh -T git@username02     # 预期:Hi 账号二登录名!
```

`Hi` 后面的名字就是该密钥对应的**真实 GitHub 登录名**,以此为准。两条都返回各自账号的名字,路由就配置成功了。

第二条测试的排错:

| 现象 | 原因 | 处理 |
| --- | --- | --- |
| 输出的还是账号一的名字 | `Host username02` 段落没生效,或密钥文件路径写错 | 检查 `IdentityFile` 路径与 `ssh-keygen -f` 生成的文件名是否一致 |
| `Permission denied (publickey)` | 新公钥没添加到新账号(或加错了账号) | 登录**新账号**打开 settings/keys,确认 `id_ed25519_username02.pub` 内容已添加 |
| `Could not resolve hostname github2` | config 里没有该 Host 段落 | 检查 `~/.ssh/config` 第二个段落是否保存完整 |

### 4.3 仓库级身份配置(user.name / user.email)

进入仓库目录,**去掉 `--global`**,只对该仓库生效:

```bash
cd ~/你的仓库目录
git config user.name "账号二的登录名"
git config user.email "账号二的邮箱"
git config --list    # 验证:仓库级值覆盖全局值
```

进阶:想让某目录下所有仓库自动使用账号二身份,在 `~/.gitconfig` 末尾加条件包含:

```ini
[includeIf "gitdir:~/你的仓库目录/"]
    path = ~/.gitconfig-account2
```

再新建 `~/.gitconfig-account2`,写入账号二的 `user.name` / `user.email`,进入对应目录自动生效。

### 4.4 仓库操作:用别名克隆 / 切换远程地址

```bash
# 新克隆:主机部分用别名,冒号后写真实登录名
git clone git@username02:账号二登录名/仓库名.git

# 已克隆的仓库:切换远程地址
cd ~/已有仓库目录
git remote set-url origin git@username02:账号二登录名/仓库名.git
git remote -v    # 验证
```

> 关键:地址中**冒号前是别名**(对应 ssh config 的 `Host`),**冒号后是真实登录名**(对应 GitHub 账号)。
> 两者可以不同——例如别名叫 `username02`,登录名实际是 `user02`,地址就是 `git@username02:user02/xxxx.git`。

### 4.5 HTTPS 方式的多账号(备选)

HTTPS 认证与 URL 中的用户名绑定,切换账号直接改远程地址,git 会按不同 URL 分别记住凭证:

```bash
git remote set-url origin https://账号二登录名@github.com/账号二登录名/仓库名.git
```

### 4.6 提交失败排查(决策流程)

**第一步:读报错,定位问题**

| 报错 | 含义 | 排查方向 |
| --- | --- | --- |
| `Permission to 仓库.git denied to Y` | 本次认证的账号 Y 没有该仓库写权限(仓库存在且公开,但 Y 不是所属账号) | 密钥走错了账号,或仓库归属搞错 |
| `Repository not found` | 仓库不存在,或为私有且该账号无权限 | 核实仓库路径与归属账号 |
| `Could not resolve hostname 别名` | 远程地址里的别名在 config 中没有对应 Host 段 | 检查 ~/.ssh/config |
| `Permission denied (publickey)` | 密钥没被 GitHub 识别(未添加/加错账号/路径错) | 检查公钥添加与 IdentityFile |
| `Bad owner or permissions on ~/.ssh/config` | 文件权限过宽 | `chmod 600 ~/.ssh/config` |

**第二步:三个检查命令**

```bash
git remote -v                 # 主机部分是哪个别名?冒号后是哪个账号名?
ssh -T git@username01         # 默认密钥对应哪个账号?
ssh -T git@别名                # 新账号密钥对应哪个账号?
```

**第三步:按原则修复**。核心原则:**推送用的密钥必须属于仓库所属的账号**。仓库在哪个账号名下,remote 地址的主机部分就用那个账号的别名,且 `ssh -T git@该别名` 必须输出该账号的登录名。

**实战案例回顾**:push 报 `Permission to user02/WiFiDevelopmentNotes.git denied to username01`,排查结论:(1) remote 地址主机部分是 `github.com`,走了第一把密钥(username01),而仓库属于 `user02`;(2) 真实登录名不是以为的 `username02`,而是 `ssh -T` 输出的 `user02`。修复只需一条命令:

```bash
git remote set-url origin git@username02:user02/WiFiDevelopmentNotes.git
git push -u origin main
```
