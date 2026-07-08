#!/usr/bin/env bash
#
# uninstall.sh — 卸载 MySQL 8.0.42 服务器（对应 install.sh 的官方社区仓库安装）
#
# 支持系统：Ubuntu / Debian / Rocky Linux / CentOS / macOS
#           （Windows 请用 winget uninstall / 控制面板）
#
# 严格对应安装脚本：先校验在装版本确为 8.0.42（不符时默认中止,避免误删他版）,
# 再停止服务 → 移除 mysql-community-* 包 → 清理本脚本添加的官方仓库配置与
# keyring。数据目录默认保留；PURGE=1 才连同数据/配置一起清理。
#
# 用法：
#   ./uninstall.sh                 # 停服务并卸载 MySQL 8.0.42（保留数据目录）
#   FORCE=1 ./uninstall.sh         # 在装版本与 8.0.42 不符时也强制卸载
#   PURGE=1 ./uninstall.sh         # 连同配置与数据目录一起清理（危险,不可恢复）
#
set -euo pipefail

MYSQL_VERSION="8.0.42"                       # 精确版本,与所在目录名一致
MYSQL_SERIES="${MYSQL_VERSION%.*}"           # 派生系列号：8.0

log()  { printf '\033[0;32m[uninstall]\033[0m %s\n' "$*"; }
warn() { printf '\033[0;33m[uninstall]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[0;31m[uninstall]\033[0m %s\n' "$*" >&2; exit 1; }

# ---- 探测操作系统（与 install.sh 一致）------------------------------------
detect_os() {
  case "$(uname -s)" in
    Linux)  OS="linux" ;;
    Darwin) OS="darwin" ;;
    MINGW*|MSYS*|CYGWIN*)
      die "检测到 Windows。请使用 winget uninstall --id Oracle.MySQL 或控制面板卸载。" ;;
    *) die "不支持的操作系统：$(uname -s)" ;;
  esac
}

# ---- 探测包管理器（与 install.sh 一致）------------------------------------
detect_pm() {
  if   command -v apt-get >/dev/null 2>&1; then PM="apt"
  elif command -v dnf     >/dev/null 2>&1; then PM="dnf"
  elif command -v yum     >/dev/null 2>&1; then PM="yum"
  elif command -v brew    >/dev/null 2>&1; then PM="brew"
  else die "未找到受支持的包管理器（apt-get / dnf / yum / brew）"; fi
}

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
      die "需要 root 权限卸载系统包,且未找到 sudo,请以 root 重试。"
    fi
  fi
}

installed_version() {
  local v=""
  if command -v mysqld >/dev/null 2>&1; then v="$(mysqld --version 2>/dev/null | grep -oE 'Ver [0-9]+\.[0-9]+\.[0-9]+' | awk '{print $2}')"; fi
  [ -z "$v" ] && command -v mysql >/dev/null 2>&1 && v="$(mysql --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1)"
  printf '%s' "$v"
}

# ---- 停止服务（与安装时的服务名对应）--------------------------------------
stop_service() {
  if [ "$PM" = "brew" ]; then
    log "brew services stop mysql@${MYSQL_SERIES} ..."
    brew services stop "mysql@${MYSQL_SERIES}" 2>/dev/null || true
    return
  fi
  for svc in mysqld mysql; do
    if command -v systemctl >/dev/null 2>&1; then
      $SUDO systemctl disable --now "$svc" 2>/dev/null || true
    else
      $SUDO service "$svc" stop 2>/dev/null || true
    fi
  done
}

# ---- 各包管理器的卸载动作 --------------------------------------------------
remove_apt() {
  export DEBIAN_FRONTEND=noninteractive
  if [ -n "${PURGE:-}" ]; then
    log "apt-get purge mysql-community-* ..."
    $SUDO apt-get purge -y 'mysql-community-*' 'mysql-client*' 'mysql-common' || $SUDO apt-get purge -y mysql-community-server
  else
    log "apt-get remove mysql-community-server ..."
    $SUDO apt-get remove -y mysql-community-server 'mysql-community-*' || true
  fi
  $SUDO apt-get autoremove -y || true
  log "移除 MySQL APT 仓库配置与 keyring ..."
  $SUDO rm -f /etc/apt/sources.list.d/mysql.list /etc/apt/keyrings/mysql.gpg
  $SUDO apt-get update -y || true
}

remove_el() {
  local pm="$1"
  if [ -n "${PURGE:-}" ]; then
    log "${pm} remove mysql-community-* ..."
    $SUDO "$pm" remove -y 'mysql-community-*' || $SUDO "$pm" remove -y mysql-community-server || true
  else
    log "${pm} remove mysql-community-server ..."
    $SUDO "$pm" remove -y mysql-community-server || true
  fi
  log "移除 MySQL 社区版 release 仓库包 ..."
  $SUDO "$pm" remove -y "mysql${MYSQL_SERIES//./}-community-release" 2>/dev/null || true
}

remove_brew(){
  if brew list --formula "mysql@${MYSQL_SERIES}" >/dev/null 2>&1; then
    log "brew uninstall mysql@${MYSQL_SERIES} ..."; brew uninstall "mysql@${MYSQL_SERIES}"
  else
    warn "Homebrew 未通过 brew 安装 mysql@${MYSQL_SERIES},跳过"
  fi
}

# ---- PURGE：清理数据目录（危险）-------------------------------------------
purge_data() {
  [ -n "${PURGE:-}" ] || return 0
  local dirs
  if [ "$PM" = "brew" ]; then
    dirs=("$(brew --prefix 2>/dev/null)/var/mysql")
  else
    dirs=(/var/lib/mysql /var/log/mysql /etc/mysql /etc/my.cnf /etc/my.cnf.d)
  fi
  for d in "${dirs[@]}"; do
    [ -n "$d" ] && [ -e "$d" ] || continue
    warn "PURGE：删除数据/配置 ${d}"
    if [ "$PM" = "brew" ]; then rm -rf "${d:?}"; else $SUDO rm -rf "${d:?}"; fi
  done
}

# ---- 主流程 ----------------------------------------------------------------
detect_os
detect_pm
setup_privilege

before="$(installed_version)"
if [ -z "$before" ]; then
  warn "系统中未检测到 MySQL,仅执行仓库/数据清理（若有）"
else
  log "当前在装：MySQL ${before}（经由 ${PM}）"
  if [ "$before" != "$MYSQL_VERSION" ] && [ -z "${FORCE:-}" ]; then
    die "在装版本 ${before} 与本目录目标 ${MYSQL_VERSION} 不一致,已中止。
如确认要卸载它,请用 FORCE=1 ./uninstall.sh 重跑,或改用对应版本目录下的脚本。"
  fi
fi

stop_service

case "$PM" in
  apt)  remove_apt ;;
  dnf)  remove_el dnf ;;
  yum)  remove_el yum ;;
  brew) remove_brew ;;
esac

purge_data

# ---- 结果 ------------------------------------------------------------------
after="$(installed_version)"
if [ -z "$after" ]; then
  log "MySQL ${MYSQL_VERSION} 卸载完成"
  [ -z "${PURGE:-}" ] && log "数据目录已保留（如 /var/lib/mysql）；如需彻底清理请用 PURGE=1 重跑。"
else
  warn "PATH 中仍存在 mysql：$(command -v mysqld 2>/dev/null || command -v mysql)（${after}）"
  warn "可能来自其他安装方式（发行版自带包、源码编译、Docker 等）,需另行处理。"
fi
