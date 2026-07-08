#!/usr/bin/env bash
#
# install.sh — 安装 MySQL 8.0.42 服务器（官方 MySQL 社区版仓库,锁定精确版本）
#
# 支持系统：Ubuntu / Debian / Rocky Linux / CentOS / macOS
#           （Windows 请用 winget/官方安装包,见文末提示）
#
# 锁定到精确小版本 8.0.42。发行版自带仓库不保证该版本,故统一从 MySQL 官方
# 社区仓库（repo.mysql.com / dev.mysql.com）按完整版本号选包安装。
#
# 注意：MySQL 官方滚动仓库通常只保留每个系列的“最新补丁版”。若 8.0.42 已被
#       更新的补丁版取代而从仓库移除,脚本会明确报错而不会装成其它版本。
# macOS：Homebrew 仅提供系列级 formula（mysql@8.0）,补丁号可能不完全等于
#       8.0.42,脚本会安装后校验并在不一致时告警。
#
# 用法：
#   ./install.sh                 # 安装 MySQL 8.0.42 服务器并启动
#   START=0 ./install.sh         # 仅安装,不自动启动/设置开机自启
#   MYSQL_RPM_REL=5 ./install.sh # EL 系覆盖 release rpm 的小版本号（默认见下）
#
set -euo pipefail

MYSQL_VERSION="8.0.42"                       # 精确版本,与所在目录名一致
MYSQL_SERIES="${MYSQL_VERSION%.*}"           # 派生系列号：8.0
MYSQL_RPM_REL="${MYSQL_RPM_REL:-1}"          # EL release rpm 的 -N 后缀,可按需覆盖
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
      die "检测到 Windows。请使用 winget 安装,例如：
         winget install --id Oracle.MySQL -e -v ${MYSQL_VERSION}" ;;
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

installed_version() {
  local v=""
  if command -v mysqld >/dev/null 2>&1; then v="$(mysqld --version 2>/dev/null | grep -oE 'Ver [0-9]+\.[0-9]+\.[0-9]+' | awk '{print $2}')"; fi
  [ -z "$v" ] && command -v mysql >/dev/null 2>&1 && v="$(mysql --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1)"
  printf '%s' "$v"
}

# ---- 各包管理器的安装动作 --------------------------------------------------
install_apt() {
  export DEBIAN_FRONTEND=noninteractive
  . /etc/os-release
  local distro="${ID}"          # ubuntu / debian
  local codename="${VERSION_CODENAME:-}"
  [ -n "$codename" ] || codename="$(command -v lsb_release >/dev/null 2>&1 && lsb_release -sc || true)"
  [ -n "$codename" ] || die "无法确定发行版代号（codename）,请手动配置 MySQL APT 仓库"
  case "$distro" in ubuntu|debian) ;; *) distro="ubuntu" ;; esac

  log "准备 MySQL APT 官方仓库（${distro}/${codename},组件 mysql-${MYSQL_SERIES}）"
  $SUDO apt-get update -y
  $SUDO apt-get install -y curl gnupg ca-certificates

  $SUDO install -d -m 0755 /etc/apt/keyrings
  curl -fsSL https://repo.mysql.com/RPM-GPG-KEY-mysql-2023 \
    | $SUDO gpg --dearmor -o /etc/apt/keyrings/mysql.gpg
  $SUDO chmod 0644 /etc/apt/keyrings/mysql.gpg

  local list=/etc/apt/sources.list.d/mysql.list
  {
    echo "deb [signed-by=/etc/apt/keyrings/mysql.gpg] http://repo.mysql.com/apt/${distro}/ ${codename} mysql-${MYSQL_SERIES}"
    echo "deb [signed-by=/etc/apt/keyrings/mysql.gpg] http://repo.mysql.com/apt/${distro}/ ${codename} mysql-tools"
  } | $SUDO tee "$list" >/dev/null
  $SUDO apt-get update -y

  # 从仓库解析出以 8.0.42 开头的完整版本串（形如 8.0.42-1ubuntu22.04）
  local full
  full="$(apt-cache madison mysql-community-server 2>/dev/null \
            | awk '{print $3}' | grep -E "^${MYSQL_VERSION}([.-]|$)" | head -n1 || true)"
  [ -n "$full" ] || die "APT 仓库中未找到 ${MYSQL_VERSION}（仓库通常只保留最新补丁版）。可用版本：
$(apt-cache madison mysql-community-server 2>/dev/null | awk '{print "  "$3}' | head -n5)"

  log "apt-get 安装 mysql-community-server=${full} ..."
  $SUDO apt-get install -y \
    "mysql-community-server=${full}" \
    "mysql-community-client=${full}" \
    "mysql-community-client-core=${full}" \
    "mysql-client=${full}" \
    "mysql-community-server-core=${full}" \
    "mysql-common=${full}" 2>/dev/null \
    || $SUDO apt-get install -y "mysql-community-server=${full}"
  SERVICE="mysql"
}

# EL(RHEL 系) 通用：装官方 release rpm、禁用内置 mysql 模块、按精确版本装 server
install_el() {
  local pm="$1"
  local elver; elver="$(rpm -E %{rhel} 2>/dev/null || true)"
  [ -n "$elver" ] || die "无法确定 EL 版本（rpm -E %{rhel} 为空）"
  local relrpm="https://dev.mysql.com/get/mysql${MYSQL_SERIES//./}-community-release-el${elver}-${MYSQL_RPM_REL}.noarch.rpm"

  log "导入 MySQL GPG key ..."
  $SUDO rpm --import https://repo.mysql.com/RPM-GPG-KEY-mysql-2023 2>/dev/null || true

  log "安装 MySQL 社区版 release 仓库：${relrpm}"
  $SUDO "$pm" install -y "$relrpm" \
    || die "安装 release rpm 失败,请确认版本号（可用 MYSQL_RPM_REL 覆盖,如 MYSQL_RPM_REL=5）"

  if [ "$pm" = "dnf" ] && $SUDO dnf module list mysql >/dev/null 2>&1; then
    $SUDO dnf module disable -y mysql || true
  fi

  # 按精确版本选包；仓库无此补丁版时报错并列出可用版本
  if ! $SUDO "$pm" list --showduplicates mysql-community-server 2>/dev/null \
        | grep -qE "[[:space:]]${MYSQL_VERSION}-"; then
    warn "仓库中未直接列出 ${MYSQL_VERSION},尝试直接按名安装,失败则说明该补丁版已被移除。"
  fi
  log "${pm} 安装 mysql-community-server-${MYSQL_VERSION} ..."
  $SUDO "$pm" install -y --nogpgcheck "mysql-community-server-${MYSQL_VERSION}" \
    || die "${pm} 无法安装 mysql-community-server-${MYSQL_VERSION}（仓库通常只保留最新补丁版）。可用版本：
$($SUDO "$pm" list --showduplicates mysql-community-server 2>/dev/null | awk '/mysql-community-server/{print "  "$2}' | head -n5)"
  SERVICE="mysqld"
}

install_brew() {
  log "brew 安装 mysql@${MYSQL_SERIES} ..."
  brew install "mysql@${MYSQL_SERIES}"
  brew link --overwrite --force "mysql@${MYSQL_SERIES}" 2>/dev/null || true
  SERVICE="mysql@${MYSQL_SERIES}"
  local got; got="$(installed_version)"
  if [ -n "$got" ] && [ "$got" != "$MYSQL_VERSION" ]; then
    warn "Homebrew 仅提供系列级 formula,装到的是 ${got},与目标 ${MYSQL_VERSION} 不一致。"
    warn "如必须精确到 ${MYSQL_VERSION},请改用官方 dmg/tar 包或 Linux 上的官方仓库。"
  fi
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

log "经由 ${PM} 安装 MySQL ${MYSQL_VERSION} 服务器（官方社区仓库）"

case "$PM" in
  apt)  install_apt ;;
  dnf)  install_el dnf ;;
  yum)  install_el yum ;;
  brew) install_brew ;;
esac

start_service

# ---- 验证 ------------------------------------------------------------------
got="$(installed_version)"
[ -n "$got" ] || die "安装后未找到 mysqld/mysql 命令"
if [ "$got" != "$MYSQL_VERSION" ]; then
  warn "检测到的版本为 ${got},与目标 ${MYSQL_VERSION} 不一致,请检查仓库/包版本。"
else
  log "版本校验通过：${got}"
fi
log "安装完成：MySQL ${got}（$(command -v mysqld 2>/dev/null || command -v mysql)）"
log "后续可运行安全加固向导：sudo mysql_secure_installation"
