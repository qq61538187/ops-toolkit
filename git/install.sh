#!/usr/bin/env bash
#
# install.sh — 安装 Git（系统包管理器，默认版本）
#
# 支持系统：Ubuntu / Debian / Rocky Linux / CentOS / macOS
#           （Windows 请用 winget/官方安装包，见文末提示）
#
# 默认安装发行版仓库（macOS 为 Homebrew）当前提供的 Git 版本，不锁定具体版本。
# Ubuntu/Debian 如需更新的 Git，可用 USE_PPA=1 启用 ppa:git-core/ppa。
#
# 用法：
#   ./install.sh                 # 用系统包管理器安装默认版本的 git
#   USE_PPA=1 ./install.sh       # Ubuntu/Debian：先加 ppa:git-core/ppa 再装（更新）
#
set -euo pipefail

log()  { printf '\033[0;32m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[0;33m[install]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[0;31m[install]\033[0m %s\n' "$*" >&2; exit 1; }

# ---- 探测操作系统 ----------------------------------------------------------
detect_os() {
  case "$(uname -s)" in
    Linux)  OS="linux" ;;
    Darwin) OS="darwin" ;;
    MINGW*|MSYS*|CYGWIN*)
      die "检测到 Windows。请使用 winget 安装，例如：
         winget install --id Git.Git -e" ;;
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
    [ "$(id -u)" -eq 0 ] && die "Homebrew 不能以 root 运行，请用普通用户执行。"
    return
  fi
  if [ "$(id -u)" -ne 0 ]; then
    if command -v sudo >/dev/null 2>&1; then
      SUDO="sudo"
    else
      die "需要 root 权限安装系统包，且未找到 sudo，请以 root 重试。"
    fi
  fi
}

installed_version() {
  command -v git >/dev/null 2>&1 || return 0
  git --version 2>/dev/null | awk '{print $3}'
}

# ---- 各包管理器的安装动作 --------------------------------------------------
install_apt() {
  export DEBIAN_FRONTEND=noninteractive
  if [ -n "${USE_PPA:-}" ]; then
    log "启用 git-core PPA（可获取更新的 Git 版本）"
    if ! command -v add-apt-repository >/dev/null 2>&1; then
      $SUDO apt-get update -y
      $SUDO apt-get install -y software-properties-common
    fi
    $SUDO add-apt-repository -y ppa:git-core/ppa || warn "添加 PPA 失败，改用发行版自带仓库"
  fi
  log "apt-get 安装 git ..."
  $SUDO apt-get update -y
  $SUDO apt-get install -y git
}

install_dnf() { log "dnf 安装 git ...";  $SUDO dnf install -y git; }
install_yum() { log "yum 安装 git ...";  $SUDO yum install -y git; }
install_brew(){ log "brew 安装 git ..."; brew install git; }

# ---- 主流程 ----------------------------------------------------------------
detect_os
detect_pm
setup_privilege

log "经由 ${PM} 安装 git（默认版本）"

case "$PM" in
  apt)  install_apt ;;
  dnf)  install_dnf ;;
  yum)  install_yum ;;
  brew) install_brew ;;
esac

# ---- 验证 ------------------------------------------------------------------
actual="$(installed_version)"
[ -n "$actual" ] || die "安装后未找到 git 命令"

log "安装完成：git ${actual}（$(command -v git)）"
if [ -z "${USE_PPA:-}" ] && [ "$PM" = "apt" ]; then
  log "如需更新的 Git，可执行： USE_PPA=1 ./install.sh"
fi
