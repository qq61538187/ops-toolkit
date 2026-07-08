# Git 安装与代理

通过系统包管理器安装 Git（默认版本），支持 Ubuntu / Debian / Rocky Linux / CentOS / macOS。

## 安装

```bash
# 本地
./install.sh

# 远程（无需 clone）
curl -fsSL https://raw.githubusercontent.com/qq61538187/ops-toolkit/main/git/install.sh | sudo bash
```

Ubuntu / Debian 需要较新版本时：

```bash
USE_PPA=1 ./install.sh
```

## 全局代理

Git 走 HTTP/HTTPS 协议拉取仓库，代理地址填本地 HTTP 代理即可（端口按实际代理软件为准，mihomo 默认为 `7890`）。

**设置全局代理：**

```bash
git config --global http.proxy  http://127.0.0.1:7890
git config --global https.proxy http://127.0.0.1:7890
```

若代理为 SOCKS5（mihomo 默认为 `7891`）：

```bash
git config --global http.proxy  socks5://127.0.0.1:7891
git config --global https.proxy socks5://127.0.0.1:7891
```

**取消全局代理：**

```bash
git config --global --unset http.proxy
git config --global --unset https.proxy
```

**查看当前配置：**

```bash
git config --global --get http.proxy
git config --global --get https.proxy
```

## 卸载

```bash
sudo ./uninstall.sh
```
