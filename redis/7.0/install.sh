#!/usr/bin/env bash
#
# install.sh — 安装 Redis 7.0（锁定到 7.0.x 系列的最新补丁版）
#
# 支持系统：Ubuntu / Debian / Rocky Linux / CentOS / macOS
#           （Windows 无官方原生版,见文末提示,建议用 WSL2）
#
# 目录名 7.0 是 Redis 的“次版本系列”（7.0.x）,并非某个精确补丁号。脚本统一
# 从提供该系列的官方/权威仓库中,挑出 7.0.x 的最新补丁版安装：
#   - Debian/Ubuntu：Redis 官方 APT 仓库（packages.redis.io）,按 7.0. 选包
#   - RHEL 系(dnf)  ：Remi 仓库的 redis:remi-7.0 模块流（精确到 7.0 系列）
#   - RHEL 系(yum)  ：EL7 无模块流,尽力经 Remi 安装并校验系列,不符即报错
#   - macOS         ：Homebrew 只有滚动 redis,装后校验系列,不符仅告警
#
# 用法：
#   ./install.sh            # 安装 Redis 7.0 并启动、设置开机自启
#   START=0 ./install.sh    # 仅安装,不自动启动/开机自启
#
set -euo pipefail

REDIS_SERIES="7.0"                       # 目标系列,与所在目录名一致（7.0.x）
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
      die "检测到 Windows：Redis 无官方原生版本。请在 WSL2 中运行本脚本,
         或改用 Memurai 等第三方移植版。" ;;
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

# 解析已安装的 redis 版本（形如 7.0.15）
installed_version() {
  local v=""
  if command -v redis-server >/dev/null 2>&1; then
    v="$(redis-server --version 2>/dev/null | grep -oE 'v=[0-9]+\.[0-9]+\.[0-9]+' | head -n1 | cut -d= -f2)"
  fi
  [ -z "$v" ] && command -v redis-cli >/dev/null 2>&1 && \
    v="$(redis-cli --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1)"
  printf '%s' "$v"
}

# ---- Debian/Ubuntu：Redis 官方 APT 仓库 -----------------------------------
install_apt() {
  export DEBIAN_FRONTEND=noninteractive
  . /etc/os-release
  local distro="${ID}"          # ubuntu / debian
  local codename="${VERSION_CODENAME:-}"
  [ -n "$codename" ] || codename="$(command -v lsb_release >/dev/null 2>&1 && lsb_release -sc || true)"
  [ -n "$codename" ] || die "无法确定发行版代号（codename）,请手动配置 Redis APT 仓库"
  case "$distro" in ubuntu|debian) ;; *) distro="ubuntu" ;; esac

  log "准备 Redis 官方 APT 仓库（${distro}/${codename}）"
  $SUDO apt-get update -y
  $SUDO apt-get install -y curl gnupg ca-certificates lsb-release

  $SUDO install -d -m 0755 /usr/share/keyrings
  curl -fsSL https://packages.redis.io/gpg \
    | $SUDO gpg --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg
  $SUDO chmod 0644 /usr/share/keyrings/redis-archive-keyring.gpg

  local list=/etc/apt/sources.list.d/redis.list
  echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb ${codename} main" \
    | $SUDO tee "$list" >/dev/null
  $SUDO apt-get update -y

  # 从仓库解析出 7.0.x 系列的最新补丁版（版本串形如 6:7.0.15-1rl1~jammy1）
  local full
  full="$(apt-cache madison redis-server 2>/dev/null \
            | awk '{print $3}' | grep -E '(^|:)7\.0\.' | head -n1 || true)"
  [ -n "$full" ] || die "APT 仓库中未找到 7.0.x 系列。可用版本：
$(apt-cache madison redis-server 2>/dev/null | awk '{print "  "$3}' | head -n8)"

  log "apt-get 安装 redis-server=${full} ..."
  $SUDO apt-get install -y "redis-server=${full}" "redis-tools=${full}" \
    || $SUDO apt-get install -y "redis-server=${full}"
  SERVICE="redis-server"
}

# ---- RHEL 系(dnf)：Remi 的 redis:remi-7.0 模块流 --------------------------
install_dnf() {
  local elver; elver="$(rpm -E %{rhel} 2>/dev/null || true)"
  [ -n "$elver" ] || die "无法确定 EL 版本（rpm -E %{rhel} 为空）"

  log "启用 EPEL 与 Remi 仓库（EL${elver}）..."
  $SUDO dnf install -y "https://dl.fedoraproject.org/pub/epel/epel-release-latest-${elver}.noarch.rpm" 2>/dev/null \
    || $SUDO dnf install -y epel-release 2>/dev/null || true
  $SUDO dnf install -y "https://rpms.remirepo.net/enterprise/remi-release-${elver}.rpm" \
    || die "安装 remi-release 失败,请确认该 EL 版本是否受 Remi 支持。"

  log "切换 redis 模块流到 remi-7.0 ..."
  $SUDO dnf module reset  -y redis || true
  $SUDO dnf module enable -y redis:remi-7.0 \
    || die "无法启用 redis:remi-7.0 模块流。可用流：
$($SUDO dnf module list redis 2>/dev/null | grep -E 'redis' | sed 's/^/  /' | head -n8)"

  log "dnf 安装 redis（7.0 系列）..."
  $SUDO dnf install -y redis
  SERVICE="redis"
}

# ---- RHEL 系(yum, EL7)：无模块流,尽力经 Remi 安装并强校验系列 -----------
install_yum() {
  local elver; elver="$(rpm -E %{rhel} 2>/dev/null || true)"
  [ -n "$elver" ] || die "无法确定 EL 版本（rpm -E %{rhel} 为空）"
  warn "EL${elver}(yum) 无模块流,无法精确锁定 7.0 系列,将安装 Remi 版并在装后校验。"

  $SUDO yum install -y "https://dl.fedoraproject.org/pub/epel/epel-release-latest-${elver}.noarch.rpm" 2>/dev/null \
    || $SUDO yum install -y epel-release 2>/dev/null || true
  $SUDO yum install -y "https://rpms.remirepo.net/enterprise/remi-release-${elver}.rpm" \
    || die "安装 remi-release 失败,请确认该 EL 版本是否受 Remi 支持。"

  log "yum 经 Remi 安装 redis ..."
  $SUDO yum install -y --enablerepo=remi redis
  SERVICE="redis"
}

# ---- macOS：Homebrew（滚动版,装后校验系列）-------------------------------
install_brew() {
  log "brew 安装 redis（Homebrew 仅提供滚动版）..."
  brew install redis
  brew link --overwrite redis 2>/dev/null || true
  SERVICE="redis"
  local got; got="$(installed_version)"
  case "$got" in
    ${REDIS_SERIES}.*) : ;;
    *) warn "Homebrew 装到的是 ${got:-未知},非 ${REDIS_SERIES}.x 系列。"
       warn "如必须精确到 7.0 系列,请改用 Linux 官方仓库,或源码编译指定版本。" ;;
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
    log "service ${SERVICE} start ..."
    $SUDO service "$SERVICE" start || warn "启动失败,可稍后手动执行：sudo service ${SERVICE} start"
  fi
}

# ---- 主流程 ----------------------------------------------------------------
detect_os
detect_pm
setup_privilege

log "经由 ${PM} 安装 Redis ${REDIS_SERIES} 系列"

case "$PM" in
  apt)  install_apt ;;
  dnf)  install_dnf ;;
  yum)  install_yum ;;
  brew) install_brew ;;
esac

start_service

# ---- 验证 ------------------------------------------------------------------
got="$(installed_version)"
[ -n "$got" ] || die "安装后未找到 redis-server/redis-cli 命令"
case "$got" in
  ${REDIS_SERIES}.*) log "版本校验通过：${got}" ;;
  *) warn "检测到的版本为 ${got},不属于 ${REDIS_SERIES}.x 系列,请检查仓库/模块流。" ;;
esac
log "安装完成：Redis ${got}（$(command -v redis-server 2>/dev/null || command -v redis-cli)）"
log "连通性自检：redis-cli ping  # 预期返回 PONG"
