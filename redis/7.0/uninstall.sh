#!/usr/bin/env bash
#
# uninstall.sh — 卸载 Redis 7.0（对应 install.sh 的安装方式反向清理）
#
# 支持系统：Ubuntu / Debian / Rocky Linux / CentOS / macOS
#           （Windows：请在 WSL2 内或对应移植版自带的方式卸载）
#
# 严格对应安装脚本：先校验在装版本确为 7.0.x 系列（不符时默认中止,避免误删
# 他版）,再停止服务 → 移除 redis 包 → 清理本脚本添加的仓库配置/keyring。
# 数据目录默认保留；PURGE=1 才连同数据/配置一起清理。
#
# 用法：
#   ./uninstall.sh            # 停服务并卸载 Redis 7.0（保留数据目录）
#   FORCE=1 ./uninstall.sh    # 在装版本非 7.0.x 时也强制卸载
#   PURGE=1 ./uninstall.sh    # 连同配置与数据目录一起清理（危险,不可恢复）
#
set -euo pipefail

REDIS_SERIES="7.0"                       # 目标系列,与所在目录名一致（7.0.x）

log()  { printf '\033[0;32m[uninstall]\033[0m %s\n' "$*"; }
warn() { printf '\033[0;33m[uninstall]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[0;31m[uninstall]\033[0m %s\n' "$*" >&2; exit 1; }

# ---- 探测操作系统（与 install.sh 一致）------------------------------------
detect_os() {
  case "$(uname -s)" in
    Linux)  OS="linux" ;;
    Darwin) OS="darwin" ;;
    MINGW*|MSYS*|CYGWIN*)
      die "检测到 Windows：请在 WSL2 内或对应移植版自带方式卸载。" ;;
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
  if command -v redis-server >/dev/null 2>&1; then
    v="$(redis-server --version 2>/dev/null | grep -oE 'v=[0-9]+\.[0-9]+\.[0-9]+' | head -n1 | cut -d= -f2)"
  fi
  [ -z "$v" ] && command -v redis-cli >/dev/null 2>&1 && \
    v="$(redis-cli --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1)"
  printf '%s' "$v"
}

# ---- 停止服务（与安装时的服务名对应）--------------------------------------
stop_service() {
  if [ "$PM" = "brew" ]; then
    log "brew services stop redis ..."
    brew services stop redis 2>/dev/null || true
    return
  fi
  for svc in redis-server redis; do
    if command -v systemctl >/dev/null 2>&1; then
      $SUDO systemctl disable --now "$svc" 2>/dev/null || true
    else
      $SUDO service "$svc" stop 2>/dev/null || true
    fi
  done
}

# ---- Debian/Ubuntu：卸载并移除官方 APT 仓库配置 ---------------------------
remove_apt() {
  export DEBIAN_FRONTEND=noninteractive
  if [ -n "${PURGE:-}" ]; then
    log "apt-get purge redis-server redis-tools ..."
    $SUDO apt-get purge -y redis-server redis-tools redis 2>/dev/null || \
      $SUDO apt-get purge -y redis-server || true
  else
    log "apt-get remove redis-server redis-tools ..."
    $SUDO apt-get remove -y redis-server redis-tools redis 2>/dev/null || \
      $SUDO apt-get remove -y redis-server || true
  fi
  $SUDO apt-get autoremove -y || true
  log "移除 Redis 官方 APT 仓库配置与 keyring ..."
  $SUDO rm -f /etc/apt/sources.list.d/redis.list /usr/share/keyrings/redis-archive-keyring.gpg
  $SUDO apt-get update -y || true
}

# ---- RHEL 系(dnf)：卸载并复位 redis 模块流 --------------------------------
remove_dnf() {
  log "dnf remove redis ..."
  $SUDO dnf remove -y redis || true
  log "复位 redis 模块流（remi-7.0 → 默认）..."
  $SUDO dnf module reset -y redis || true
}

# ---- RHEL 系(yum, EL7)：卸载 Remi 版 redis --------------------------------
remove_yum() {
  log "yum remove redis ..."
  $SUDO yum remove -y redis || true
}

# ---- macOS：Homebrew --------------------------------------------------------
remove_brew() {
  if brew list --formula redis >/dev/null 2>&1; then
    log "brew uninstall redis ..."; brew uninstall redis
  else
    warn "Homebrew 未通过 brew 安装 redis,跳过"
  fi
}

# ---- PURGE：清理数据/配置目录（危险）-------------------------------------
purge_data() {
  [ -n "${PURGE:-}" ] || return 0
  local dirs
  if [ "$PM" = "brew" ]; then
    dirs=("$(brew --prefix 2>/dev/null)/var/db/redis" "$(brew --prefix 2>/dev/null)/etc/redis.conf")
  else
    dirs=(/var/lib/redis /var/log/redis /etc/redis /etc/redis.conf)
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
  warn "系统中未检测到 Redis,仅执行仓库/数据清理（若有）"
else
  log "当前在装：Redis ${before}（经由 ${PM}）"
  case "$before" in
    ${REDIS_SERIES}.*) : ;;
    *)
      if [ -z "${FORCE:-}" ]; then
        die "在装版本 ${before} 与本目录目标 ${REDIS_SERIES}.x 不一致,已中止。
如确认要卸载它,请用 FORCE=1 ./uninstall.sh 重跑,或改用对应版本目录下的脚本。"
      fi ;;
  esac
fi

stop_service

case "$PM" in
  apt)  remove_apt ;;
  dnf)  remove_dnf ;;
  yum)  remove_yum ;;
  brew) remove_brew ;;
esac

purge_data

# ---- 结果 ------------------------------------------------------------------
after="$(installed_version)"
if [ -z "$after" ]; then
  log "Redis ${REDIS_SERIES} 卸载完成"
  [ -z "${PURGE:-}" ] && log "数据目录已保留（如 /var/lib/redis）；如需彻底清理请用 PURGE=1 重跑。"
else
  warn "PATH 中仍存在 redis：$(command -v redis-server 2>/dev/null || command -v redis-cli)（${after}）"
  warn "可能来自其他安装方式（发行版自带包、源码编译、Docker 等）,需另行处理。"
fi
