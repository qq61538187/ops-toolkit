#!/usr/bin/env bash
#
# uninstall.sh — 卸载 Docker Engine 28.4.0（含 compose 插件,对应 install.sh）
#
# 支持系统：Ubuntu / Debian / Rocky Linux / CentOS / macOS
#           （Windows：请从「应用和功能」卸载 Docker Desktop）
#
# 严格对应安装脚本：先校验在装引擎确为 28.4.0（不符时默认中止,避免误删他版）,
# 再停止服务 → 移除 docker-ce/-cli/containerd.io/buildx/compose 插件 → 清理本
# 脚本添加的官方仓库配置与 keyring。镜像/容器/卷等数据默认保留；PURGE=1 才连同
# /var/lib/docker、/var/lib/containerd 一起清理。
#
# 用法：
#   ./uninstall.sh            # 停服务并卸载 Docker 28.4.0（保留镜像/容器/卷）
#   FORCE=1 ./uninstall.sh    # 在装引擎版本非 28.4.0 时也强制卸载
#   PURGE=1 ./uninstall.sh    # 连同镜像/容器/卷等数据一起清理（危险,不可恢复）
#
set -euo pipefail

DOCKER_VERSION="28.4.0"                   # 精确版本,与所在目录名一致

log()  { printf '\033[0;32m[uninstall]\033[0m %s\n' "$*"; }
warn() { printf '\033[0;33m[uninstall]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[0;31m[uninstall]\033[0m %s\n' "$*" >&2; exit 1; }

# ---- 探测操作系统（与 install.sh 一致）------------------------------------
detect_os() {
  case "$(uname -s)" in
    Linux)  OS="linux" ;;
    Darwin) OS="darwin" ;;
    MINGW*|MSYS*|CYGWIN*)
      die "检测到 Windows：请从「应用和功能」卸载 Docker Desktop。" ;;
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
  if command -v docker >/dev/null 2>&1; then
    v="$(docker version --format '{{.Server.Version}}' 2>/dev/null || true)"
    [ -n "$v" ] || v="$(docker --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1)"
  fi
  printf '%s' "$v"
}

# ---- 停止服务（与安装时对应）----------------------------------------------
stop_service() {
  if [ "$PM" = "brew" ]; then
    log "macOS：请手动退出 Docker Desktop 应用。"
    return
  fi
  for svc in docker docker.socket containerd; do
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
  local pkgs="docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras"
  if [ -n "${PURGE:-}" ]; then
    log "apt-get purge docker 相关包 ..."
    $SUDO apt-get purge -y $pkgs 2>/dev/null || $SUDO apt-get remove -y $pkgs || true
  else
    log "apt-get remove docker 相关包 ..."
    $SUDO apt-get remove -y $pkgs || true
  fi
  $SUDO apt-get autoremove -y || true
  log "移除 Docker 官方 APT 仓库配置与 keyring ..."
  $SUDO rm -f /etc/apt/sources.list.d/docker.list /etc/apt/keyrings/docker.gpg
  $SUDO apt-get update -y || true
}

# ---- RHEL 系(dnf/yum)：卸载并移除官方 YUM 仓库配置 ------------------------
remove_el() {
  local pm="$1"
  local pkgs="docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras"
  log "${pm} remove docker 相关包 ..."
  $SUDO "$pm" remove -y $pkgs || true
  log "移除 Docker 官方 YUM 仓库配置 ..."
  $SUDO rm -f /etc/yum.repos.d/docker-ce.repo
}

# ---- macOS：Homebrew Cask ---------------------------------------------------
remove_brew() {
  if brew list --cask docker >/dev/null 2>&1; then
    log "brew uninstall --cask docker ..."; brew uninstall --cask docker
  else
    warn "Homebrew 未通过 Cask 安装 docker,跳过"
  fi
}

# ---- PURGE：清理镜像/容器/卷等数据（危险）--------------------------------
purge_data() {
  [ -n "${PURGE:-}" ] || return 0
  [ "$PM" = "brew" ] && { warn "macOS 数据由 Docker Desktop 管理,请在应用内 Troubleshoot → Reset 清理。"; return 0; }
  local dirs=(/var/lib/docker /var/lib/containerd /etc/docker /var/run/docker.sock)
  for d in "${dirs[@]}"; do
    [ -n "$d" ] && [ -e "$d" ] || continue
    warn "PURGE：删除数据 ${d}"
    $SUDO rm -rf "${d:?}"
  done
}

# ---- 主流程 ----------------------------------------------------------------
detect_os
detect_pm
setup_privilege

before="$(installed_version)"
if [ -z "$before" ]; then
  warn "系统中未检测到 Docker,仅执行仓库/数据清理（若有）"
else
  log "当前在装：Docker Engine ${before}（经由 ${PM}）"
  if [ "$before" != "$DOCKER_VERSION" ] && [ -z "${FORCE:-}" ]; then
    die "在装引擎版本 ${before} 与本目录目标 ${DOCKER_VERSION} 不一致,已中止。
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
if [ -z "$after" ] || [ "$PM" = "brew" ]; then
  log "Docker ${DOCKER_VERSION} 卸载完成"
  [ -z "${PURGE:-}" ] && [ "$PM" != "brew" ] && \
    log "镜像/容器/卷数据已保留（/var/lib/docker）；如需彻底清理请用 PURGE=1 重跑。"
else
  warn "PATH 中仍存在 docker：$(command -v docker)（${after}）"
  warn "可能来自其他安装方式（发行版自带包、snap、二进制、Docker Desktop 等）,需另行处理。"
fi
