#!/usr/bin/env bash
#
# uninstall.sh — 卸载 Node.js 22.15.0（对应 install.sh 的官方预编译二进制安装）
#
# 支持系统：Ubuntu / Debian / Rocky Linux / CentOS / macOS
#           （Windows Server 请改用 PowerShell 版本，见文末提示）
#
# 用法：
#   ./uninstall.sh                # 从 /usr/local 卸载
#   PREFIX=/opt ./uninstall.sh    # 与安装时相同的自定义前缀
#
set -euo pipefail

NODE_VERSION="22.15.0"
PREFIX="${PREFIX:-/usr/local}"
NODEJS_HOME="${PREFIX}/lib/nodejs"
BIN_DIR="${PREFIX}/bin"
BINARIES=(node npm npx corepack)

log()  { printf '\033[0;32m[uninstall]\033[0m %s\n' "$*"; }
warn() { printf '\033[0;33m[uninstall]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[0;31m[uninstall]\033[0m %s\n' "$*" >&2; exit 1; }

# 需要 root 权限写入 PREFIX 时自动使用 sudo
SUDO=""
if [ "$(id -u)" -ne 0 ]; then
  if command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
  else
    warn "非 root 用户且系统无 sudo，若删除 ${PREFIX} 下文件失败请以 root 重试"
  fi
fi

# ---- 探测操作系统与架构（与 install.sh 保持一致）---------------------------
detect_platform() {
  local os arch
  case "$(uname -s)" in
    Linux)  os="linux" ;;
    Darwin) os="darwin" ;;
    MINGW*|MSYS*|CYGWIN*)
      die "检测到 Windows。请使用 PowerShell 卸载，例如：
         winget uninstall OpenJS.NodeJS" ;;
    *) die "不支持的操作系统：$(uname -s)" ;;
  esac

  case "$(uname -m)" in
    x86_64|amd64)  arch="x64" ;;
    aarch64|arm64) arch="arm64" ;;
    armv7l)        arch="armv7l" ;;
    ppc64le)       arch="ppc64le" ;;
    s390x)         arch="s390x" ;;
    *) die "不支持的 CPU 架构：$(uname -m)" ;;
  esac

  PLATFORM="${os}-${arch}"
}

# ---- 主流程 ----------------------------------------------------------------
detect_platform

DIST_NAME="node-v${NODE_VERSION}-${PLATFORM}"
INSTALL_DIR="${NODEJS_HOME}/${DIST_NAME}"
removed_any=0

# 移除软链接：仅删除确实指向本次安装目录的链接，避免误删其他 Node 安装
log "清理 ${BIN_DIR} 下的软链接 ..."
for bin in "${BINARIES[@]}"; do
  link="${BIN_DIR}/${bin}"
  [ -L "$link" ] || continue
  target="$(readlink "$link" 2>/dev/null || true)"
  case "$target" in
    "${INSTALL_DIR}/bin/${bin}")
      $SUDO rm -f "$link"
      log "已移除软链接：${link}"
      removed_any=1
      ;;
    *)
      warn "跳过 ${link}（指向 ${target:-未知}，非本次安装）"
      ;;
  esac
done

# 移除安装目录
if [ -d "$INSTALL_DIR" ]; then
  log "删除安装目录：${INSTALL_DIR}"
  $SUDO rm -rf "${INSTALL_DIR:?}"
  removed_any=1
else
  warn "未找到安装目录：${INSTALL_DIR}"
fi

# 若 NODEJS_HOME 已空则一并清理
if [ -d "$NODEJS_HOME" ] && [ -z "$(ls -A "$NODEJS_HOME" 2>/dev/null)" ]; then
  $SUDO rmdir "$NODEJS_HOME" 2>/dev/null && log "已移除空目录：${NODEJS_HOME}" || true
fi

# ---- 结果 ------------------------------------------------------------------
if [ "$removed_any" -eq 1 ]; then
  log "Node.js v${NODE_VERSION} 卸载完成"
else
  warn "未发现 Node.js v${NODE_VERSION}（PREFIX=${PREFIX}）的安装痕迹，无需卸载"
fi

if command -v node >/dev/null 2>&1; then
  warn "PATH 中仍存在 node：$(command -v node)（$(node --version 2>/dev/null || echo '?')），可能来自其他安装方式"
fi
