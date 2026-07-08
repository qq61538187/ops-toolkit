#!/usr/bin/env bash
#
# uninstall.sh — 卸载 nginx 1.31（对应 install.sh 的官方仓库安装方式反向清理）
#
# 支持系统：Ubuntu / Debian / Rocky Linux / CentOS / macOS
#           （Windows：删除解压出的 nginx 目录即可）
#
# 严格对应安装脚本：先校验在装版本确为 1.31.x 系列（不符时默认中止,避免误删
# 他版）,再停止服务 → 移除 nginx 包 → 清理本脚本添加的仓库/keyring/pin 配置。
# 数据/配置/日志默认保留；PURGE=1 才连同一起清理。
#
# 用法：
#   ./uninstall.sh            # 停服务并卸载 nginx 1.31（保留配置/日志）
#   FORCE=1 ./uninstall.sh    # 在装版本非 1.31.x 时也强制卸载
#   PURGE=1 ./uninstall.sh    # 连同配置/日志目录一起清理（危险,不可恢复）
#
set -euo pipefail

NGINX_SERIES="1.31"                      # 目标系列,与所在目录名一致（1.31.x）

log()  { printf '\033[0;32m[uninstall]\033[0m %s\n' "$*"; }
warn() { printf '\033[0;33m[uninstall]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[0;31m[uninstall]\033[0m %s\n' "$*" >&2; exit 1; }

# ---- 探测操作系统（与 install.sh 一致）------------------------------------
detect_os() {
  case "$(uname -s)" in
    Linux)  OS="linux" ;;
    Darwin) OS="darwin" ;;
    MINGW*|MSYS*|CYGWIN*)
      die "检测到 Windows：直接删除解压出的 nginx 目录即可。" ;;
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
  if command -v nginx >/dev/null 2>&1; then
    v="$(nginx -v 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1)"
  fi
  printf '%s' "$v"
}

# ---- 停止服务（与安装时对应）----------------------------------------------
stop_service() {
  if [ "$PM" = "brew" ]; then
    log "brew services stop nginx ..."
    brew services stop nginx 2>/dev/null || true
    return
  fi
  if command -v systemctl >/dev/null 2>&1; then
    $SUDO systemctl disable --now nginx 2>/dev/null || true
  else
    # 无 systemd（如容器）：优雅退出 nginx 主进程
    $SUDO nginx -s quit 2>/dev/null || $SUDO service nginx stop 2>/dev/null || true
  fi
}

# ---- Debian/Ubuntu：卸载并移除官方 APT 仓库/keyring/pin -------------------
remove_apt() {
  export DEBIAN_FRONTEND=noninteractive
  if [ -n "${PURGE:-}" ]; then
    log "apt-get purge nginx ..."
    $SUDO apt-get purge -y nginx || true
  else
    log "apt-get remove nginx ..."
    $SUDO apt-get remove -y nginx || true
  fi
  $SUDO apt-get autoremove -y || true
  log "移除 nginx 官方 APT 仓库配置、keyring 与 pin ..."
  $SUDO rm -f /etc/apt/sources.list.d/nginx.list \
              /usr/share/keyrings/nginx-archive-keyring.gpg \
              /etc/apt/preferences.d/99nginx
  $SUDO apt-get update -y || true
}

# ---- RHEL 系(dnf/yum)：卸载并移除官方 YUM 仓库配置 ------------------------
remove_el() {
  local pm="$1"
  log "${pm} remove nginx ..."
  $SUDO "$pm" remove -y nginx || true
  log "移除 nginx 官方 YUM 仓库配置 ..."
  $SUDO rm -f /etc/yum.repos.d/nginx.repo
}

# ---- macOS：Homebrew --------------------------------------------------------
remove_brew() {
  if brew list --formula nginx >/dev/null 2>&1; then
    log "brew uninstall nginx ..."; brew uninstall nginx
  else
    warn "Homebrew 未通过 brew 安装 nginx,跳过"
  fi
}

# ---- PURGE：清理配置/日志目录（危险）-------------------------------------
purge_data() {
  [ -n "${PURGE:-}" ] || return 0
  local dirs
  if [ "$PM" = "brew" ]; then
    dirs=("$(brew --prefix 2>/dev/null)/etc/nginx" "$(brew --prefix 2>/dev/null)/var/log/nginx")
  else
    dirs=(/etc/nginx /var/log/nginx /var/cache/nginx)
  fi
  for d in "${dirs[@]}"; do
    [ -n "$d" ] && [ -e "$d" ] || continue
    warn "PURGE：删除配置/日志 ${d}"
    if [ "$PM" = "brew" ]; then rm -rf "${d:?}"; else $SUDO rm -rf "${d:?}"; fi
  done
}

# ---- 主流程 ----------------------------------------------------------------
detect_os
detect_pm
setup_privilege

before="$(installed_version)"
if [ -z "$before" ]; then
  warn "系统中未检测到 nginx,仅执行仓库/数据清理（若有）"
else
  log "当前在装：nginx ${before}（经由 ${PM}）"
  case "$before" in
    ${NGINX_SERIES}.*) : ;;
    *)
      if [ -z "${FORCE:-}" ]; then
        die "在装版本 ${before} 与本目录目标 ${NGINX_SERIES}.x 不一致,已中止。
如确认要卸载它,请用 FORCE=1 ./uninstall.sh 重跑,或改用对应版本目录下的脚本。"
      fi ;;
  esac
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
  log "nginx ${NGINX_SERIES} 卸载完成"
  [ -z "${PURGE:-}" ] && log "配置/日志已保留（如 /etc/nginx、/var/log/nginx）；如需彻底清理请用 PURGE=1 重跑。"
else
  warn "PATH 中仍存在 nginx：$(command -v nginx)（${after}）"
  warn "可能来自其他安装方式（发行版自带包、源码编译、Docker 等）,需另行处理。"
fi
