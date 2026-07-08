#!/usr/bin/env bash
#
# install.sh — 安装 Node.js 22.15.0（官方预编译二进制）
#
# 支持系统：Ubuntu / Debian / Rocky Linux / CentOS / macOS
#           （Windows Server 请改用 PowerShell 版本，见文末提示）
#
# 用法：
#   ./install.sh                # 安装到 /usr/local
#   PREFIX=/opt ./install.sh    # 自定义安装前缀
#
set -euo pipefail

NODE_VERSION="22.15.0"
PREFIX="${PREFIX:-/usr/local}"
NODEJS_HOME="${PREFIX}/lib/nodejs"
BIN_DIR="${PREFIX}/bin"
BINARIES=(node npm npx corepack)

log()  { printf '\033[0;32m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[0;33m[install]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[0;31m[install]\033[0m %s\n' "$*" >&2; exit 1; }

# 需要 root 权限写入 PREFIX 时自动使用 sudo
SUDO=""
if [ "$(id -u)" -ne 0 ]; then
  if command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
  else
    warn "非 root 用户且系统无 sudo，若写入 ${PREFIX} 失败请以 root 重试"
  fi
fi

# ---- 探测操作系统与架构 ----------------------------------------------------
detect_platform() {
  local os arch
  case "$(uname -s)" in
    Linux)  os="linux" ;;
    Darwin) os="darwin" ;;
    MINGW*|MSYS*|CYGWIN*)
      die "检测到 Windows。请使用 PowerShell 安装，例如：
         winget install OpenJS.NodeJS --version ${NODE_VERSION}" ;;
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

# ---- 下载工具 --------------------------------------------------------------
download() {
  local url="$1" out="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -fSL --retry 3 -o "$out" "$url"
  elif command -v wget >/dev/null 2>&1; then
    wget -O "$out" "$url"
  else
    die "未找到 curl 或 wget，无法下载"
  fi
}

# ---- 主流程 ----------------------------------------------------------------
detect_platform

# 已安装同版本则跳过
if command -v node >/dev/null 2>&1 && [ "$(node --version 2>/dev/null)" = "v${NODE_VERSION}" ]; then
  log "Node.js v${NODE_VERSION} 已安装：$(command -v node)"
  exit 0
fi

DIST_NAME="node-v${NODE_VERSION}-${PLATFORM}"
TARBALL="${DIST_NAME}.tar.gz"
URL="https://nodejs.org/dist/v${NODE_VERSION}/${TARBALL}"
SHASUMS_URL="https://nodejs.org/dist/v${NODE_VERSION}/SHASUMS256.txt"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

log "目标平台：${PLATFORM}"
log "下载：${URL}"
download "$URL" "${TMP_DIR}/${TARBALL}"

# 校验 SHA256（下载失败不阻断安装，仅告警）
if download "$SHASUMS_URL" "${TMP_DIR}/SHASUMS256.txt" 2>/dev/null; then
  log "校验 SHA256 ..."
  expected="$(grep "  ${TARBALL}\$" "${TMP_DIR}/SHASUMS256.txt" | awk '{print $1}')"
  if [ -n "$expected" ]; then
    if command -v sha256sum >/dev/null 2>&1; then
      actual="$(sha256sum "${TMP_DIR}/${TARBALL}" | awk '{print $1}')"
    elif command -v shasum >/dev/null 2>&1; then
      actual="$(shasum -a 256 "${TMP_DIR}/${TARBALL}" | awk '{print $1}')"
    else
      actual=""
      warn "无 sha256sum/shasum，跳过校验"
    fi
    if [ -n "$actual" ] && [ "$actual" != "$expected" ]; then
      die "SHA256 校验失败：期望 ${expected}，实际 ${actual}"
    fi
    [ -n "$actual" ] && log "SHA256 校验通过"
  fi
else
  warn "无法获取 SHASUMS256.txt，跳过校验"
fi

log "解压 ..."
tar -xzf "${TMP_DIR}/${TARBALL}" -C "$TMP_DIR"

log "安装到 ${NODEJS_HOME}/${DIST_NAME}"
$SUDO mkdir -p "$NODEJS_HOME"
$SUDO rm -rf "${NODEJS_HOME:?}/${DIST_NAME}"
$SUDO mv "${TMP_DIR}/${DIST_NAME}" "${NODEJS_HOME}/"

log "创建软链接到 ${BIN_DIR}"
$SUDO mkdir -p "$BIN_DIR"
for bin in "${BINARIES[@]}"; do
  if [ -e "${NODEJS_HOME}/${DIST_NAME}/bin/${bin}" ]; then
    $SUDO ln -sf "${NODEJS_HOME}/${DIST_NAME}/bin/${bin}" "${BIN_DIR}/${bin}"
  fi
done

# ---- 验证 ------------------------------------------------------------------
if [ -x "${BIN_DIR}/node" ]; then
  log "安装完成：node $("${BIN_DIR}/node" --version) / npm $("${BIN_DIR}/npm" --version 2>/dev/null || echo '?')"
  case ":${PATH}:" in
    *":${BIN_DIR}:"*) ;;
    *) warn "${BIN_DIR} 不在 PATH 中，请将其加入 PATH：export PATH=\"${BIN_DIR}:\$PATH\"" ;;
  esac
else
  die "安装后未找到 ${BIN_DIR}/node"
fi
