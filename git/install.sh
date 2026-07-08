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

# ---- CentOS 8 EOL 守卫 -----------------------------------------------------
# CentOS Linux 8 已于 2021-12-31 EOL,各镜像站(含云厂商内网镜像)删除或搬迁了
# 8 的仓库内容,dnf 拉 repodata/repomd.xml 会 404。官方存档在 vault.centos.org。
is_centos8() {
  if grep -qi 'release 8' /etc/centos-release 2>/dev/null; then return 0; fi
  [ -r /etc/os-release ] || return 1
  grep -qi 'centos' /etc/os-release && grep -q '^VERSION_ID="8"' /etc/os-release
}

is_centos_stream8() {
  grep -qi 'stream' /etc/centos-release 2>/dev/null && return 0
  [ -r /etc/os-release ] && grep -qi 'stream' /etc/os-release
}

# vault 上 CentOS Linux 8 的最终版本目录;Stream 8 走 8-stream 目录
vault_base() {
  if is_centos_stream8; then
    printf 'https://vault.centos.org/8-stream'
  else
    printf 'https://vault.centos.org/8.5.2111'
  fi
}

# 打印手动修复命令(默认路径,不改系统)
print_vault_fix_hint() {
  local base; base="$(vault_base)"
  cat >&2 <<EOF

  # 1) 备份现有仓库配置
  sudo cp -a /etc/yum.repos.d /root/yum.repos.d.bak.\$(date +%s)

  # 2) 关掉失效的 mirrorlist,baseurl 指向 vault 存档
  sudo sed -i \\
    -e 's|^mirrorlist=|#mirrorlist=|g' \\
    -e 's|^#\\?baseurl=https\\?://[^/]*/\\([^/]*/\\)\\?\\\$releasever|baseurl=${base}|g' \\
    /etc/yum.repos.d/CentOS-*.repo

  # 3) 重建缓存后重跑本脚本
  sudo dnf clean all && sudo dnf makecache

EOF
}

# 自动修复(仅在 FIX_EOL_REPO=1 时调用):备份 → 切 vault → 重建缓存
fix_centos8_repo_to_vault() {
  local base bak
  base="$(vault_base)"
  bak="/etc/yum.repos.d.bak.$(date +%s)"
  log "FIX_EOL_REPO=1:备份 /etc/yum.repos.d → ${bak}"
  $SUDO cp -a /etc/yum.repos.d "$bak"
  log "把 CentOS 仓库 baseurl 切换到 ${base} ..."
  # $releasever 前可能带一个路径段:jdcloud 用 /centos/$releasever,官方用 /$contentdir/$releasever
  $SUDO sed -i \
    -e 's|^mirrorlist=|#mirrorlist=|g' \
    -e "s|^#\\?baseurl=https\\?://[^/]*/\\([^/]*/\\)\\?\$releasever|baseurl=${base}|g" \
    /etc/yum.repos.d/CentOS-*.repo
  $SUDO dnf clean all
  $SUDO dnf makecache
}

# dnf/yum 安装失败后,若判定为 CentOS 8 EOL 仓库问题则介入处理
handle_centos8_eol() {
  is_centos8 || return 1   # 不是 CentOS 8,交回上层按普通失败处理
  warn "检测到 CentOS 8 已 EOL —— 镜像仓库元数据不可用(通常报 404)。"
  warn "官方仓库已迁移到 vault.centos.org。"
  if [ -z "${FIX_EOL_REPO:-}" ]; then
    warn "默认不修改系统仓库。手动修复(切到 vault 后重跑本脚本):"
    print_vault_fix_hint
    die "或用 FIX_EOL_REPO=1 让脚本自动备份并切换 vault:
       curl -fsSL <url>/git/install.sh | sudo FIX_EOL_REPO=1 bash"
  fi
  fix_centos8_repo_to_vault
  return 0
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

install_dnf() {
  log "dnf 安装 git ..."
  if $SUDO dnf install -y git; then return 0; fi
  # 失败:可能是 CentOS 8 EOL 仓库失效
  handle_centos8_eol || die "dnf 安装 git 失败(非 CentOS 8 EOL 场景),请检查网络与仓库配置。"
  log "dnf 安装 git（切换 vault 后重试）..."
  $SUDO dnf install -y git
}
install_yum() {
  log "yum 安装 git ..."
  if $SUDO yum install -y git; then return 0; fi
  handle_centos8_eol || die "yum 安装 git 失败(非 CentOS 8 EOL 场景),请检查网络与仓库配置。"
  log "yum 安装 git（切换 vault 后重试）..."
  $SUDO yum install -y git
}
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
