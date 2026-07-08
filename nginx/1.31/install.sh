#!/usr/bin/env bash
#
# install.sh — 安装 nginx 1.31（锁定到 1.31.x 主线/mainline 系列的最新补丁版）
#
# 支持系统：Ubuntu / Debian / Rocky Linux / CentOS / macOS
#           （Windows 请用官方 zip 包,见文末提示）
#
# 目录名 1.31 是 nginx 的“次版本系列”（1.31.x）,并非某个精确补丁号。1.31 属于
# nginx 的 mainline(主线)版本,脚本统一从 nginx 官方仓库的 mainline 通道里,
# 挑出 1.31.x 的最新补丁版安装：
#   - Debian/Ubuntu：nginx 官方 APT 仓库 packages（mainline）,按 1.31. 选包
#   - RHEL 系(dnf/yum)：nginx 官方 YUM 仓库（mainline）,按 1.31 系列选包
#   - macOS          ：Homebrew 只有滚动 nginx,装后校验系列,不符仅告警
#
# 用法：
#   ./install.sh            # 安装 nginx 1.31 并启动、设置开机自启
#   START=0 ./install.sh    # 仅安装,不自动启动/开机自启
#
set -euo pipefail

NGINX_SERIES="1.31"                      # 目标系列,与所在目录名一致（1.31.x）
NGINX_CHANNEL="mainline"                 # 1.31 属于主线；官方仓库分 mainline / (stable)
START="${START:-1}"

log()  { printf '\033[0;32m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[0;33m[install]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[0;31m[install]\033[0m %s\n' "$*" >&2; exit 1; }

# ---- 探测操作系统 ----------------------------------------------------------
detect_os() {
  case "$(uname -s)" in
    Linux)  OS="linux" ;;
    Darwin) OS="darwin" ;;
    MINGW*|MSYS*|CYGWIN*)
      die "检测到 Windows：请下载官方 zip 版 nginx/Windows-${NGINX_SERIES}.x：
         https://nginx.org/en/download.html" ;;
    *) die "不支持的操作系统：$(uname -s)" ;;
  esac
}

# ---- 探测包管理器 ----------------------------------------------------------
detect_pm() {
  if   command -v apt-get >/dev/null 2>&1; then PM="apt"
  elif command -v dnf     >/dev/null 2>&1; then PM="dnf"
  elif command -v yum     >/dev/null 2>&1; then PM="yum"
  elif command -v brew    >/dev/null 2>&1; then PM="brew"
  else die "未找到受支持的包管理器（apt-get / dnf / yum / brew）"; fi
}

# ---- root / sudo 处理 ------------------------------------------------------
# apt/dnf/yum 需要 root 写系统目录；brew 反之绝不能用 root。
setup_privilege() {
  SUDO=""
  if [ "$PM" = "brew" ]; then
    [ "$(id -u)" -eq 0 ] && die "Homebrew 不能以 root 运行,请用普通用户执行。"
    return
  fi
  if [ "$(id -u)" -ne 0 ]; then
    if command -v sudo >/dev/null 2>&1; then
      SUDO="sudo"
    else
      die "需要 root 权限安装系统包,且未找到 sudo,请以 root 重试。"
    fi
  fi
}

# 解析已安装的 nginx 版本（形如 1.31.2）
installed_version() {
  local v=""
  if command -v nginx >/dev/null 2>&1; then
    v="$(nginx -v 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1)"
  fi
  printf '%s' "$v"
}

# ---- Debian/Ubuntu：nginx 官方 APT 仓库（mainline）------------------------
install_apt() {
  export DEBIAN_FRONTEND=noninteractive
  . /etc/os-release
  local distro="${ID}"          # ubuntu / debian
  local codename="${VERSION_CODENAME:-}"
  [ -n "$codename" ] || codename="$(command -v lsb_release >/dev/null 2>&1 && lsb_release -sc || true)"
  [ -n "$codename" ] || die "无法确定发行版代号（codename）,请手动配置 nginx APT 仓库"
  case "$distro" in ubuntu|debian) ;; *) distro="ubuntu" ;; esac

  log "准备 nginx 官方 APT 仓库（${NGINX_CHANNEL}, ${distro}/${codename}）"
  $SUDO apt-get update -y
  $SUDO apt-get install -y curl gnupg2 ca-certificates lsb-release debian-archive-keyring 2>/dev/null \
    || $SUDO apt-get install -y curl gnupg2 ca-certificates lsb-release

  $SUDO install -d -m 0755 /usr/share/keyrings
  curl -fsSL https://nginx.org/keys/nginx_signing.key \
    | $SUDO gpg --dearmor -o /usr/share/keyrings/nginx-archive-keyring.gpg
  $SUDO chmod 0644 /usr/share/keyrings/nginx-archive-keyring.gpg

  local list=/etc/apt/sources.list.d/nginx.list
  echo "deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] http://nginx.org/packages/${NGINX_CHANNEL}/${distro}/ ${codename} nginx" \
    | $SUDO tee "$list" >/dev/null
  # 官方仓库优先级钉高,避免被发行版自带 nginx 覆盖
  echo -e "Package: *\nPin: origin nginx.org\nPin-Priority: 900" \
    | $SUDO tee /etc/apt/preferences.d/99nginx >/dev/null
  $SUDO apt-get update -y

  # 从仓库解析出 1.31.x 系列的最新补丁版（版本串形如 1.31.2-1~jammy）
  local full
  full="$(apt-cache madison nginx 2>/dev/null \
            | awk '{print $3}' | grep -E "^${NGINX_SERIES//./\\.}\\." | head -n1 || true)"
  [ -n "$full" ] || die "APT 仓库中未找到 ${NGINX_SERIES}.x 系列。可用版本：
$(apt-cache madison nginx 2>/dev/null | awk '{print "  "$3}' | head -n8)"

  log "apt-get 安装 nginx=${full} ..."
  $SUDO apt-get install -y "nginx=${full}"
  SERVICE="nginx"
}

# ---- RHEL 系(dnf/yum)：nginx 官方 YUM 仓库（mainline）---------------------
install_el() {
  local pm="$1"
  local elver; elver="$(rpm -E %{rhel} 2>/dev/null || true)"
  [ -n "$elver" ] || die "无法确定 EL 版本（rpm -E %{rhel} 为空）"

  # mainline 通道对应 repo 目录 packages/mainline/centos/<elver>/
  local baseurl="http://nginx.org/packages/${NGINX_CHANNEL}/centos/${elver}/\$basearch/"
  log "写入 nginx 官方 YUM 仓库（${NGINX_CHANNEL}, EL${elver}）..."
  $SUDO tee /etc/yum.repos.d/nginx.repo >/dev/null <<EOF
[nginx]
name=nginx ${NGINX_CHANNEL} repo
baseurl=${baseurl}
gpgcheck=1
enabled=1
gpgkey=https://nginx.org/keys/nginx_signing.key
module_hotfixes=true
EOF

  # 从仓库解析出 1.31.x 系列的最新补丁版
  local full
  full="$($SUDO "$pm" --showduplicates list nginx 2>/dev/null \
            | awk '/nginx/{print $2}' | grep -E "^([0-9]+:)?${NGINX_SERIES//./\\.}\\." | tail -n1 || true)"
  if [ -n "$full" ]; then
    log "${pm} 安装 nginx-${full}（${NGINX_SERIES} 系列最新补丁）..."
    $SUDO "$pm" install -y "nginx-${full}"
  else
    warn "未能从仓库列出 ${NGINX_SERIES}.x,尝试直接安装 nginx 并在装后校验系列。"
    $SUDO "$pm" install -y nginx
  fi
  SERVICE="nginx"
}

# ---- macOS：Homebrew（滚动版,装后校验系列）-------------------------------
install_brew() {
  log "brew 安装 nginx（Homebrew 仅提供滚动版）..."
  brew install nginx
  brew link --overwrite nginx 2>/dev/null || true
  SERVICE="nginx"
  local got; got="$(installed_version)"
  case "$got" in
    ${NGINX_SERIES}.*) : ;;
    *) warn "Homebrew 装到的是 ${got:-未知},非 ${NGINX_SERIES}.x 系列。"
       warn "如必须精确到 ${NGINX_SERIES} 系列,请改用 Linux 官方仓库,或源码编译指定版本。" ;;
  esac
}

# ---- 启动并设置开机自启 ----------------------------------------------------
start_service() {
  [ "$START" = "1" ] || { log "START=0,跳过启动/开机自启"; return; }
  if [ "$PM" = "brew" ]; then
    log "brew services start ${SERVICE} ..."
    brew services start "$SERVICE" || warn "启动失败,可稍后手动执行：brew services start ${SERVICE}"
    return
  fi
  if command -v systemctl >/dev/null 2>&1; then
    log "systemctl enable --now ${SERVICE} ..."
    $SUDO systemctl enable --now "$SERVICE" \
      || warn "启动失败,可稍后手动执行：sudo systemctl enable --now ${SERVICE}"
  else
    # 无 systemd（如容器）：直接拉起 nginx 主进程
    log "直接启动 nginx ..."
    $SUDO nginx || $SUDO service nginx start \
      || warn "启动失败,可稍后手动执行：nginx"
  fi
}

# ---- 主流程 ----------------------------------------------------------------
detect_os
detect_pm
setup_privilege

log "经由 ${PM} 安装 nginx ${NGINX_SERIES} 系列（${NGINX_CHANNEL}）"

case "$PM" in
  apt)  install_apt ;;
  dnf)  install_el dnf ;;
  yum)  install_el yum ;;
  brew) install_brew ;;
esac

start_service

# ---- 验证 ------------------------------------------------------------------
got="$(installed_version)"
[ -n "$got" ] || die "安装后未找到 nginx 命令"
case "$got" in
  ${NGINX_SERIES}.*) log "版本校验通过：${got}" ;;
  *) warn "检测到的版本为 ${got},不属于 ${NGINX_SERIES}.x 系列,请检查仓库/通道。" ;;
esac
log "安装完成：nginx ${got}（$(command -v nginx)）"
log "配置自检：nginx -t   # 校验配置文件语法"
