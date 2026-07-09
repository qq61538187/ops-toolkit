#!/usr/bin/env bash
#
# uninstall.sh — 卸载 OpenVPN（对应 install.sh 的系统包管理器安装）
#
# 支持系统：Ubuntu / Debian / Rocky Linux / CentOS
#
# 说明：通过与安装相同的包管理器移除 openvpn。默认只移除软件包，
#       不动 /etc/openvpn 下的配置与 PKI（避免误删证书/密钥）。
#       如需连同配置一起清理，用 PURGE_CONFIG=1。
#
# 用法：
#   ./uninstall.sh                    # 用系统包管理器卸载 openvpn（保留 /etc/openvpn）
#   PURGE=1 ./uninstall.sh            # apt：purge（连同包配置一起清理）
#   PURGE_CONFIG=1 ./uninstall.sh     # 额外删除 /etc/openvpn（含证书/密钥，谨慎！）
#   REMOVE_EPEL=1 ./uninstall.sh      # RHEL 系：连同 epel-release 一起移除
#
set -euo pipefail

log()  { printf '\033[0;32m[uninstall]\033[0m %s\n' "$*"; }
warn() { printf '\033[0;33m[uninstall]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[0;31m[uninstall]\033[0m %s\n' "$*" >&2; exit 1; }

# ---- 探测操作系统（与 install.sh 一致）------------------------------------
detect_os() {
  case "$(uname -s)" in
    Linux)  OS="linux" ;;
    Darwin) die "OpenVPN 服务端为 Linux 组件。macOS 客户端请自行卸载对应 App。" ;;
    MINGW*|MSYS*|CYGWIN*)
      die "检测到 Windows。请从控制面板卸载 OpenVPN 客户端。" ;;
    *) die "不支持的操作系统：$(uname -s)" ;;
  esac
}

# ---- 探测包管理器（与 install.sh 一致）------------------------------------
detect_pm() {
  if   command -v apt-get >/dev/null 2>&1; then PM="apt"
  elif command -v dnf     >/dev/null 2>&1; then PM="dnf"
  elif command -v yum     >/dev/null 2>&1; then PM="yum"
  else die "未找到受支持的包管理器（apt-get / dnf / yum）"; fi
}

setup_privilege() {
  SUDO=""
  if [ "$(id -u)" -ne 0 ]; then
    if command -v sudo >/dev/null 2>&1; then
      SUDO="sudo"
    else
      die "需要 root 权限卸载系统包，且未找到 sudo，请以 root 重试。"
    fi
  fi
}

installed_version() {
  command -v openvpn >/dev/null 2>&1 || return 0
  openvpn --version 2>/dev/null | head -n1 | awk '{print $2}'
}

# ---- 停止并禁用可能在跑的服务（忽略不存在的情况）--------------------------
stop_services() {
  command -v systemctl >/dev/null 2>&1 || return 0
  # 常见的 server/client 模板单元；未启用的会被静默跳过
  for unit in 'openvpn-server@*' 'openvpn-client@*' 'openvpn@*' openvpn; do
    if $SUDO systemctl list-units --all --type=service 2>/dev/null | grep -q "${unit%@*}"; then
      log "停止并禁用 ${unit} ..."
      $SUDO systemctl disable --now "$unit" 2>/dev/null || true
    fi
  done
}

# ---- 各包管理器的卸载动作 --------------------------------------------------
remove_apt() {
  export DEBIAN_FRONTEND=noninteractive
  if [ -n "${PURGE:-}" ]; then
    log "apt-get purge openvpn ..."
    $SUDO apt-get purge -y openvpn
  else
    log "apt-get remove openvpn ..."
    $SUDO apt-get remove -y openvpn
  fi
  $SUDO apt-get autoremove -y || true
}

remove_dnf() {
  log "dnf remove openvpn ..."; $SUDO dnf remove -y openvpn
  if [ -n "${REMOVE_EPEL:-}" ]; then
    log "移除 epel-release ..."; $SUDO dnf remove -y epel-release || warn "移除 epel-release 失败（可能未安装）"
  fi
}
remove_yum() {
  log "yum remove openvpn ..."; $SUDO yum remove -y openvpn
  if [ -n "${REMOVE_EPEL:-}" ]; then
    log "移除 epel-release ..."; $SUDO yum remove -y epel-release || warn "移除 epel-release 失败（可能未安装）"
  fi
}

# ---- 可选：清理配置目录 ----------------------------------------------------
purge_config_dir() {
  [ -n "${PURGE_CONFIG:-}" ] || return 0
  if [ -d /etc/openvpn ]; then
    warn "PURGE_CONFIG=1：删除 /etc/openvpn（含证书/密钥/配置）..."
    $SUDO rm -rf /etc/openvpn
  fi
}

# ---- 主流程 ----------------------------------------------------------------
detect_os
detect_pm
setup_privilege

before="$(installed_version)"
if [ -z "$before" ]; then
  warn "系统中未检测到 openvpn，无需卸载"
  # 即便包已不在，仍尊重 PURGE_CONFIG 的显式清理意图
  purge_config_dir
  exit 0
fi
log "准备卸载：openvpn ${before}（经由 ${PM}）"

stop_services

case "$PM" in
  apt)  remove_apt ;;
  dnf)  remove_dnf ;;
  yum)  remove_yum ;;
esac

purge_config_dir

# ---- 结果 ------------------------------------------------------------------
hash -r 2>/dev/null || true
after="$(installed_version)"
if [ -z "$after" ]; then
  log "OpenVPN 卸载完成"
  [ -z "${PURGE_CONFIG:-}" ] && [ -d /etc/openvpn ] && \
    log "已保留 /etc/openvpn（如需清理证书/密钥，用 PURGE_CONFIG=1 ./uninstall.sh）"
else
  warn "PATH 中仍存在 openvpn：$(command -v openvpn)（${after}）"
  warn "可能来自其他安装方式（如源码编译 /usr/local），需另行处理。"
fi
