#!/usr/bin/env bash
#
# install.sh — 安装 OpenVPN（系统包管理器，默认版本）
#
# 支持系统：Ubuntu / Debian / Rocky Linux / CentOS
#           （OpenVPN 服务端为 Linux 组件，macOS/Windows 请用客户端 App，见文末提示）
#
# 默认安装发行版仓库当前提供的 OpenVPN 版本，不锁定具体版本。
# RHEL 系（dnf/yum）的 openvpn 包位于 EPEL，本脚本会先启用 EPEL 再安装。
#
# 用法：
#   ./install.sh                 # 用系统包管理器安装默认版本的 openvpn
#   FIX_EOL_REPO=1 ./install.sh  # CentOS 8 已 EOL：自动把仓库切到 vault 后再装
#
set -euo pipefail

log()  { printf '\033[0;32m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[0;33m[install]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[0;31m[install]\033[0m %s\n' "$*" >&2; exit 1; }

# ---- 探测操作系统 ----------------------------------------------------------
detect_os() {
  case "$(uname -s)" in
    Linux)  OS="linux" ;;
    Darwin) die "OpenVPN 服务端为 Linux 组件。macOS 请安装客户端，例如：
         brew install --cask tunnelblick   # 或 OpenVPN Connect App" ;;
    MINGW*|MSYS*|CYGWIN*)
      die "检测到 Windows。请安装 OpenVPN 官方客户端（OpenVPN Connect / GUI）。" ;;
    *) die "不支持的操作系统：$(uname -s)" ;;
  esac
}

# ---- 探测包管理器 ----------------------------------------------------------
detect_pm() {
  if   command -v apt-get >/dev/null 2>&1; then PM="apt"
  elif command -v dnf     >/dev/null 2>&1; then PM="dnf"
  elif command -v yum     >/dev/null 2>&1; then PM="yum"
  else die "未找到受支持的包管理器（apt-get / dnf / yum）"; fi
}

# ---- root / sudo 处理 ------------------------------------------------------
setup_privilege() {
  SUDO=""
  if [ "$(id -u)" -ne 0 ]; then
    if command -v sudo >/dev/null 2>&1; then
      SUDO="sudo"
    else
      die "需要 root 权限安装系统包，且未找到 sudo，请以 root 重试。"
    fi
  fi
}

installed_version() {
  command -v openvpn >/dev/null 2>&1 || return 0
  # openvpn --version 首行形如: OpenVPN 2.5.9 x86_64-pc-linux-gnu ...
  openvpn --version 2>/dev/null | head -n1 | awk '{print $2}'
}

# ---- CentOS 8 EOL 守卫 -----------------------------------------------------
# CentOS Linux 8 已于 2021-12-31 EOL,镜像站删除或搬迁了 8 的仓库内容,
# dnf 拉 repodata 会 404。官方存档在 vault.centos.org。
is_centos8() {
  if grep -qi 'release 8' /etc/centos-release 2>/dev/null; then return 0; fi
  [ -r /etc/os-release ] || return 1
  grep -qi 'centos' /etc/os-release && grep -q '^VERSION_ID="8"' /etc/os-release
}

is_centos_stream8() {
  grep -qi 'stream' /etc/centos-release 2>/dev/null && return 0
  [ -r /etc/os-release ] && grep -qi 'stream' /etc/os-release
}

vault_base() {
  if is_centos_stream8; then
    printf 'https://vault.centos.org/8-stream'
  else
    printf 'https://vault.centos.org/8.5.2111'
  fi
}

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

fix_centos8_repo_to_vault() {
  local base bak
  base="$(vault_base)"
  bak="/etc/yum.repos.d.bak.$(date +%s)"
  log "FIX_EOL_REPO=1:备份 /etc/yum.repos.d → ${bak}"
  $SUDO cp -a /etc/yum.repos.d "$bak"
  log "把 CentOS 仓库 baseurl 切换到 ${base} ..."
  $SUDO sed -i \
    -e 's|^mirrorlist=|#mirrorlist=|g' \
    -e "s|^#\\?baseurl=https\\?://[^/]*/\\([^/]*/\\)\\?\$releasever|baseurl=${base}|g" \
    /etc/yum.repos.d/CentOS-*.repo
  $SUDO dnf clean all 2>/dev/null || $SUDO yum clean all
  $SUDO dnf makecache 2>/dev/null || $SUDO yum makecache
}

handle_centos8_eol() {
  is_centos8 || return 1
  warn "检测到 CentOS 8 已 EOL —— 镜像仓库元数据不可用(通常报 404)。"
  warn "官方仓库已迁移到 vault.centos.org。"
  if [ -z "${FIX_EOL_REPO:-}" ]; then
    warn "默认不修改系统仓库。手动修复(切到 vault 后重跑本脚本):"
    print_vault_fix_hint
    die "或用 FIX_EOL_REPO=1 让脚本自动备份并切换 vault:
       curl -fsSL <url>/openvpn/install.sh | sudo FIX_EOL_REPO=1 bash"
  fi
  fix_centos8_repo_to_vault
  return 0
}

# ---- EPEL：RHEL 系 openvpn 包所在仓库 --------------------------------------
ensure_epel() {
  local mgr="$1"   # dnf 或 yum
  # 已启用则跳过
  if $SUDO "$mgr" repolist enabled 2>/dev/null | grep -qi '^epel'; then
    log "EPEL 已启用"
    return 0
  fi
  log "启用 EPEL 仓库（openvpn 包所在处）..."
  if ! $SUDO "$mgr" install -y epel-release; then
    # CentOS 8 EOL 场景：base 仓库都拉不动，先切 vault 再装 epel-release
    handle_centos8_eol || die "安装 epel-release 失败，请检查网络与仓库配置。"
    $SUDO "$mgr" install -y epel-release
  fi
}

# ---- 各包管理器的安装动作 --------------------------------------------------
install_apt() {
  export DEBIAN_FRONTEND=noninteractive
  log "apt-get 安装 openvpn ..."
  $SUDO apt-get update -y
  $SUDO apt-get install -y openvpn
}

install_dnf() {
  ensure_epel dnf
  log "dnf 安装 openvpn ..."
  if $SUDO dnf install -y openvpn; then return 0; fi
  handle_centos8_eol || die "dnf 安装 openvpn 失败(非 CentOS 8 EOL 场景),请检查网络与仓库配置。"
  log "dnf 安装 openvpn（切换 vault 后重试）..."
  $SUDO dnf install -y openvpn
}

install_yum() {
  ensure_epel yum
  log "yum 安装 openvpn ..."
  if $SUDO yum install -y openvpn; then return 0; fi
  handle_centos8_eol || die "yum 安装 openvpn 失败(非 CentOS 8 EOL 场景),请检查网络与仓库配置。"
  log "yum 安装 openvpn（切换 vault 后重试）..."
  $SUDO yum install -y openvpn
}

# ---- 主流程 ----------------------------------------------------------------
detect_os
detect_pm
setup_privilege

log "经由 ${PM} 安装 openvpn（默认版本）"

case "$PM" in
  apt)  install_apt ;;
  dnf)  install_dnf ;;
  yum)  install_yum ;;
esac

# ---- 验证 ------------------------------------------------------------------
actual="$(installed_version)"
[ -n "$actual" ] || die "安装后未找到 openvpn 命令"

log "安装完成：openvpn ${actual}（$(command -v openvpn)）"
log "接下来可用 easy-rsa 生成 PKI 并编写 server.conf，详见 readme.md。"
