# mihomo 代理部署

基于 [mihomo (Clash.Meta)](https://github.com/MetaCubeX/mihomo) 内核,在 Linux 服务器上通过订阅地址部署代理,对外暴露本地 **HTTP(7890)** / **SOCKS5(7891)** 端口,供服务器上其它程序翻墙访问外网。

## 快速开始

```bash
# 1. 编辑 install.sh,把顶部的 SUB_URL 替换成你的订阅地址
vim install.sh          # 找到 SUB_URL="在此填入你的订阅地址"

# 2. 安装(只下载 + 写配置 + 注册服务,不启动)
sudo ./install.sh

# 3. 开启代理
sudo ./start.sh

# 4. 查看状态 / 确认是否真在翻墙
./status.sh
```

## 脚本一览

| 脚本 | 职责 | 说明 |
|------|------|------|
| `install.sh`   | **只装**       | 下载二进制、写配置、注册 systemd 单元(**不启动**) |
| `start.sh`     | **开启代理**   | 启动服务 + 设开机自启 + 连通性自检 |
| `status.sh`    | **查看状态**   | 只读:服务/端口/出口 IP 对比,判断是否真在翻墙 |
| `close.sh`     | **关闭代理**   | 停止服务 + 取消开机自启(**保留安装**) |
| `uninstall.sh` | **只卸**       | 停服并删除二进制 / 配置 / 服务单元 |

除 `status.sh` 外,其余脚本均需 root(`sudo`)。

## 使用代理

服务开启后,让程序走代理有两种方式:

```bash
# 方式一:环境变量(对当前 shell 及其子进程生效)
export https_proxy=http://127.0.0.1:7890
export http_proxy=http://127.0.0.1:7890
export all_proxy=socks5://127.0.0.1:7891

# 方式二:单条命令临时走代理
curl -x http://127.0.0.1:7890 https://www.google.com -I
```

> 关闭代理后记得清理环境变量,否则命令仍会尝试连已停止的代理:
> `unset http_proxy https_proxy all_proxy`

## 可配置项(环境变量)

`install.sh` 支持以下环境变量,应对服务器访问 GitHub 困难的情况:

| 变量 | 作用 | 示例 |
|------|------|------|
| `GH_MIRROR` | 指定自己的 GitHub 加速镜像(优先用它,再回退直连) | `GH_MIRROR=https://你的镜像/ ./install.sh` |
| `VERSION`   | 跳过 GitHub API 查询,直接指定内核版本 | `VERSION=v1.19.0 ./install.sh` |

默认无需设置:安装时会**先直连 GitHub,失败自动依次尝试内置镜像**(`ghfast.top` / `gh-proxy.com` / `ghproxy.net`)。

## 常用运维

```bash
systemctl status mihomo        # 服务状态
systemctl restart mihomo       # 更新订阅后重启使其重新拉取
journalctl -u mihomo -f        # 实时日志
```

- **订阅节点**:配置里 `proxy-providers` 每小时自动刷新一次;想立即刷新可 `systemctl restart mihomo`。
- **节点选择**:默认 `url-test` 自动选延迟最低的节点,无需人工干预。
- **仅本机可用**:默认 `allow-lan: false`,只监听 `127.0.0.1`。若要让局域网内其它机器也走此代理,编辑 `/etc/mihomo/config.yaml` 把 `allow-lan` 改为 `true` 并重启。

## 配置文件位置

| 路径 | 说明 |
|------|------|
| `/usr/local/bin/mihomo` | 内核二进制 |
| `/etc/mihomo/config.yaml` | 主配置 |
| `/etc/mihomo/providers/` | 订阅缓存 |
| `/etc/systemd/system/mihomo.service` | systemd 单元 |

## 端口

| 端口 | 用途 |
|------|------|
| `7890` | HTTP 代理 |
| `7891` | SOCKS5 代理 |
| `9090` | 控制接口(`external-controller`,仅本机) |
