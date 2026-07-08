#!/usr/bin/env bash
#
# mihomo (Clash.Meta) 安装脚本
# 作用:在服务器上部署 mihomo 内核,基于订阅地址拉取节点,
#       对外暴露本地 HTTP(7890) / SOCKS5(7891) 代理端口,供其它程序翻墙访问外网。
#
# 目录约定:未指定固定版本 → 默认安装 GitHub 最新 release,不建版本目录。
#
set -euo pipefail

# ============================================================================
# 【必填】把下面这行替换成你的翻墙订阅地址(Clash / mihomo 订阅链接)
# ============================================================================
SUB_URL="在此填入你的订阅地址"
# ============================================================================

# ---- 固定配置(卸载脚本 uninstall.sh 必须与这些保持一致)-------------------
BIN_PATH="/usr/local/bin/mihomo"
CONF_DIR="/etc/mihomo"
SERVICE_FILE="/etc/systemd/system/mihomo.service"
HTTP_PORT=7890
SOCKS_PORT=7891
CTRL_ADDR="127.0.0.1:9090"
REPO="MetaCubeX/mihomo"

# GitHub 访问:先直连,失败自动依次尝试下列镜像前缀(拼在完整 github URL 前面)。
# 可用环境变量 GH_MIRROR 指定自己的镜像,如:GH_MIRROR="https://your.mirror/" ./install.sh
if [ -n "${GH_MIRROR:-}" ]; then
  MIRRORS=("${GH_MIRROR%/}/" "")          # 用户指定的镜像优先,再退回直连
else
  MIRRORS=(
    ""                          # 直连 github
    "https://ghfast.top/"
    "https://gh-proxy.com/"
    "https://ghproxy.net/"
  )
fi
# 可用环境变量 VERSION 跳过 API 查询直接指定版本,如:VERSION=v1.19.0 ./install.sh
VERSION="${VERSION:-}"
# ---------------------------------------------------------------------------

log()  { printf '\033[32m[+]\033[0m %s\n' "$*"; }
warn() { printf '\033[33m[!]\033[0m %s\n' "$*"; }
die()  { printf '\033[31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

# ---- 前置检查 --------------------------------------------------------------
[ "$(id -u)" -eq 0 ] || die "请用 root 运行(sudo bash install.sh)"

if [ "$SUB_URL" = "在此填入你的订阅地址" ] || [ -z "$SUB_URL" ]; then
  die "请先编辑本脚本,把 SUB_URL 替换成你的订阅地址"
fi

command -v systemctl >/dev/null 2>&1 || die "未检测到 systemd,本脚本依赖 systemd 常驻服务"

# 下载工具:优先 curl,退化到 wget
if command -v curl >/dev/null 2>&1; then
  DL() { curl -fsSL "$1" -o "$2"; }
  FETCH() { curl -fsSL "$1"; }
elif command -v wget >/dev/null 2>&1; then
  DL() { wget -qO "$2" "$1"; }
  FETCH() { wget -qO- "$1"; }
else
  die "需要 curl 或 wget"
fi

command -v gunzip >/dev/null 2>&1 || die "需要 gunzip(gzip 包)"

# 依次用「直连 + 各镜像」尝试抓取一个完整 github URL,内容打到 stdout;全失败返回非 0
gh_fetch() {
  local url="$1" m
  for m in "${MIRRORS[@]}"; do
    if FETCH "${m}${url}"; then return 0; fi
  done
  return 1
}
# 依次用「直连 + 各镜像」尝试下载 github URL 到文件;全失败返回非 0
gh_download() {
  local url="$1" out="$2" m
  for m in "${MIRRORS[@]}"; do
    printf '\033[32m[+]\033[0m  尝试:%s\n' "${m:-直连}${url}" >&2
    if DL "${m}${url}" "$out"; then return 0; fi
  done
  return 1
}

# ---- 平台探测 --------------------------------------------------------------
case "$(uname -s)" in
  Linux) OS="linux" ;;
  *) die "本脚本仅支持 Linux 服务器" ;;
esac

case "$(uname -m)" in
  x86_64|amd64)   ARCH="amd64-compatible" ;;   # compatible 版兼容老 CPU(不要求 AVX)
  aarch64|arm64)  ARCH="arm64" ;;
  armv7*|armv7l)  ARCH="armv7" ;;
  *) die "不支持的架构:$(uname -m)" ;;
esac

# ---- 确定最新版本 ----------------------------------------------------------
if [ -z "$VERSION" ]; then
  log "查询 mihomo 最新版本..."
  # 先把响应完整读进变量再解析,避免 grep -m1 提前关闭管道导致 curl 报错 23
  API_RESP="$(gh_fetch "https://api.github.com/repos/${REPO}/releases/latest")" \
    || die "无法访问 GitHub API(直连和镜像都失败)。可手动指定版本重试:VERSION=v1.19.0 ./install.sh"
  VERSION="$(printf '%s' "$API_RESP" | grep '"tag_name"' | head -n1 \
    | sed -E 's/.*"tag_name"[^"]*"([^"]+)".*/\1/')"
  [ -n "$VERSION" ] || die "无法解析最新版本号(GitHub API 返回异常)"
fi
log "目标版本:${VERSION}"

ASSET="mihomo-${OS}-${ARCH}-${VERSION}.gz"
URL="https://github.com/${REPO}/releases/download/${VERSION}/${ASSET}"

# ---- 下载并安装二进制 ------------------------------------------------------
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

log "下载 ${ASSET} ..."
gh_download "$URL" "${TMP}/mihomo.gz" \
  || die "下载失败(直连和所有镜像都失败)。可自定义镜像重试:GH_MIRROR=https://你的镜像/ ./install.sh"

log "安装二进制到 ${BIN_PATH}"
gunzip -c "${TMP}/mihomo.gz" > "${TMP}/mihomo"
install -m 0755 "${TMP}/mihomo" "$BIN_PATH"

# ---- 写配置文件 ------------------------------------------------------------
log "生成配置 ${CONF_DIR}/config.yaml"
mkdir -p "${CONF_DIR}/providers"

cat > "${CONF_DIR}/config.yaml" <<EOF
# 由 install.sh 自动生成
port: ${HTTP_PORT}          # HTTP 代理端口
socks-port: ${SOCKS_PORT}   # SOCKS5 代理端口
allow-lan: false            # 仅本机可用;如需局域网内其它机器走代理改为 true
bind-address: '127.0.0.1'
mode: rule
log-level: info
external-controller: '${CTRL_ADDR}'

proxy-providers:
  subscription:
    type: http
    url: "${SUB_URL}"
    interval: 3600
    path: ./providers/subscription.yaml
    health-check:
      enable: true
      url: https://www.gstatic.com/generate_204
      interval: 300

proxy-groups:
  - name: PROXY
    type: url-test          # 自动选延迟最低的节点,无需人工干预
    use:
      - subscription
    url: https://www.gstatic.com/generate_204
    interval: 300
    tolerance: 50

rules:
  # 内网 / 本机流量直连,不走代理(避免依赖 GeoIP 数据库)
  - IP-CIDR,127.0.0.0/8,DIRECT,no-resolve
  - IP-CIDR,10.0.0.0/8,DIRECT,no-resolve
  - IP-CIDR,172.16.0.0/12,DIRECT,no-resolve
  - IP-CIDR,192.168.0.0/16,DIRECT,no-resolve
  # 其余全部走代理
  - MATCH,PROXY
EOF

# ---- 写 systemd 服务 -------------------------------------------------------
log "写入 systemd 服务 ${SERVICE_FILE}"
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=mihomo (Clash.Meta) proxy service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${BIN_PATH} -d ${CONF_DIR}
Restart=on-failure
RestartSec=3
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF

# ---- 注册 systemd 单元(仅注册,不启动)-----------------------------------
log "注册 systemd 单元(不自动启动)"
systemctl daemon-reload

cat <<EOF

============================================================
 mihomo 安装完成 ✅(尚未启动)
------------------------------------------------------------
 二进制  : ${BIN_PATH}
 配置    : ${CONF_DIR}/config.yaml
 服务单元: ${SERVICE_FILE}

 开启代理: ./start.sh
 关闭代理: ./close.sh
 卸载    : ./uninstall.sh
============================================================
EOF
