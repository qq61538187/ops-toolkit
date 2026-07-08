# ops-toolkit

运维工具集，支持在以下操作系统镜像上部署与运行。

## 支持的系统镜像

| 系统 | 说明 |
|------|------|
| **Ubuntu** | 默认推荐，适用于大多数 Linux 运维场景 |
| **Windows Server** | 适用于 Windows 服务与 .NET 相关部署 |
| **Debian** | 稳定、轻量，适合长期运行的 Linux 环境 |
| **Rocky Linux** | RHEL 兼容发行版，适用于企业级 Linux 环境 |
| **CentOS** | 经典 RHEL 系发行版，兼容既有 CentOS 运维习惯 |
| **macOS** | 适用于本地开发与 macOS 环境下的运维脚本执行 |

## 远程执行（无需 clone）

在云服务器上可直接拉取并执行仓库中的脚本，不必先 `git clone` 整个项目。

**通用格式**（将 `<组件>` 替换为对应目录名，如 `git`、`node`）：

```bash
curl -fsSL https://raw.githubusercontent.com/qq61538187/ops-toolkit/main/<组件>/install.sh | sudo bash
```

**示例 — 安装 Git：**

```bash
curl -fsSL https://raw.githubusercontent.com/qq61538187/ops-toolkit/main/git/install.sh | sudo bash
```

Ubuntu / Debian 如需较新版本，可加环境变量：

```bash
curl -fsSL https://raw.githubusercontent.com/qq61538187/ops-toolkit/main/git/install.sh | sudo USE_PPA=1 bash
```

**说明：**

- Linux 上多数安装脚本需要 root 权限，管道后加 `sudo bash`；若已是 `root` 用户，可省略 `sudo`。
- 卸载脚本同理，将路径中的 `install.sh` 改为 `uninstall.sh` 即可。
- 部分脚本需先修改配置再执行（如 `mihomo/install.sh` 须填入订阅地址），此类不适合直接 `curl | bash`，请先 clone 或下载后编辑再运行。


