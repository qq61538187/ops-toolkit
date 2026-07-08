#!/usr/bin/env bash
#
# uninstall.sh — 卸载 Git（对应 install.sh 的系统包管理器安装）
#
# 支持系统：Ubuntu / Debian / Rocky Linux / CentOS / macOS
#           （Windows 请用 winget uninstall / 控制面板）
#
# 说明：通过与安装相同的包管理器移除 git。若安装时用过 USE_PPA=1，可用
#       REMOVE_PPA=1 一并移除 ppa:git-core/ppa 源。
#
# 用法：
#   ./uninstall.sh                 # 用系统包管理器卸载 git
#   REMOVE_PPA=1 ./uninstall.sh    # Ubuntu/Debian：连同 git-core PPA 一起移除
#   PURGE=1 ./uninstall.sh         # apt：purge（连同配置一起清理）
#
set -euo pipefail

log()  { printf '\033[0;32m[uninstall]\033[0m %s\n' "$*"; }
warn() { printf '\033[0;33m[uninstall]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[0;31m[uninstall]\033[0m %s\n' "$*" >&2; exit 1; }

# ---- 探测操作系统（与 install.sh 一致）------------------------------------
detect_os() {
  case "$(uname -s)" in
    Linux)  OS="linux" ;;
    Darwin) OS="darwin" ;;
    MINGW*|MSYS*|CYGWIN*)
      die "检测到 Windows。请使用 winget uninstall --id Git.Git 或控制面板卸载。" ;;
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
    [ "$(id -u)" -eq 0 ] && die "Homebrew 不能以 root 运行，请用普通用户执行。"
    return
  fi
  if [ "$(id -u)" -ne 0 ]; then
    if command -v sudo >/dev/null 2>&1; then
      SUDO="sudo"
    else
      die "需要 root 权限卸载系统包，且未找到 sudo，请以 root 重试。"
    fi
  fi
}

installed_version() {
  command -v git >/dev/null 2>&1 || return 0
  git --version 2>/dev/null | awk '{print $3}'
}

# ---- 各包管理器的卸载动作 --------------------------------------------------
remove_apt() {
  export DEBIAN_FRONTEND=noninteractive
  if [ -n "${PURGE:-}" ]; then
    log "apt-get purge git ..."
    $SUDO apt-get purge -y git
  else
    log "apt-get remove git ..."
    $SUDO apt-get remove -y git
  fi
  $SUDO apt-get autoremove -y || true
  if [ -n "${REMOVE_PPA:-}" ]; then
    if command -v add-apt-repository >/dev/null 2>&1; then
      log "移除 git-core PPA ..."
      $SUDO add-apt-repository -y --remove ppa:git-core/ppa || warn "移除 PPA 失败（可能未添加）"
      $SUDO apt-get update -y || true
    else
      warn "未找到 add-apt-repository，跳过移除 PPA"
    fi
  fi
}

remove_dnf() { log "dnf remove git ..."; $SUDO dnf remove -y git; }
remove_yum() { log "yum remove git ..."; $SUDO yum remove -y git; }
remove_brew(){
  if brew list --formula git >/dev/null 2>&1; then
    log "brew uninstall git ..."; brew uninstall git
  else
    warn "Homebrew 未通过 brew 安装 git，跳过"
  fi
}

# ---- 主流程 ----------------------------------------------------------------
detect_os
detect_pm
setup_privilege

before="$(installed_version)"
if [ -z "$before" ]; then
  warn "系统中未检测到 git，无需卸载"
  exit 0
fi
log "准备卸载：git ${before}（经由 ${PM}）"

case "$PM" in
  apt)  remove_apt ;;
  dnf)  remove_dnf ;;
  yum)  remove_yum ;;
  brew) remove_brew ;;
esac

# ---- 结果 ------------------------------------------------------------------
after="$(installed_version)"
if [ -z "$after" ]; then
  log "Git 卸载完成"
else
  warn "PATH 中仍存在 git：$(command -v git)（${after}）"
  warn "可能来自其他安装方式（如源码编译 /usr/local、Xcode Command Line Tools 等），需另行处理。"
fi
