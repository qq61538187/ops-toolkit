#!/usr/bin/env bash
#
# install.sh — 安装 Docker Engine（最新版,含 docker compose v2 插件）
#
# 支持系统：Ubuntu / Debian / Rocky Linux / CentOS / macOS
#           （Windows 请用 Docker Desktop,见文末提示）
#
# 不锁定版本:安装该发行版当前提供的最新 docker-ce,一并安装官方 Compose V2 插件
# （docker compose 命令）。软件仓库默认走阿里云镜像(国内直连 download.docker.com
# 常被重置),可用 DOCKER_MIRROR 切换 tuna/ustc/official 或自定义基地址：
#   - Debian/Ubuntu：docker-ce / docker-ce-cli / containerd.io /
#                    docker-buildx-plugin / docker-compose-plugin
#   - RHEL 系(dnf/yum)：同上
#   - macOS          ：Homebrew Cask 安装 Docker Desktop（滚动最新版）
#
# 说明:docker compose 属于 Docker 官方 Compose V2 插件,命令是「docker compose」
#       （无连字符）。旧的独立二进制「docker-compose」(v1) 已 EOL,本脚本不再安装。
#
# 注意:Docker 官方已停止为 CentOS 8 / el8 发布新版,el8 通道封顶约 26.1.3。故在
#       CentOS 8 上装到的是 el8 可得的最新版,并非全网最新;如需更新版本请用
#       Rocky/Alma 9(el9) 或 Ubuntu。
#
# 用法:
#   ./install.sh                        # 安装最新版 Docker + compose 插件并启动
#   START=0 ./install.sh                # 仅安装,不自动启动/开机自启
#   DOCKER_ADD_USER=alice ./install.sh  # 额外把 alice 加入 docker 用户组
#   DOCKER_MIRROR=tuna ./install.sh     # 换清华镜像(默认 aliyun;official=官方源)
#
set -euo pipefail

START="${START:-1}"
# 国内镜像加速地址(空格分隔),写入 /etc/docker/daemon.json 的 registry-mirrors。
# 可用环境变量覆盖;显式设为空字符串(REGISTRY_MIRRORS="")则跳过该配置。
REGISTRY_MIRRORS="${REGISTRY_MIRRORS-https://docker.m.daocloud.io https://docker.1ms.run https://hub-mirror.c.163.com https://mirror.baidubce.com}"

log()  { printf '\033[0;32m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[0;33m[install]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[0;31m[install]\033[0m %s\n' "$*" >&2; exit 1; }

# Docker 「软件仓库」镜像(装 docker-ce 包本身用的源,不同于上面拉容器镜像的加速)。
# 国内直连 download.docker.com 常被重置/墙,默认走阿里云镜像;可用 DOCKER_MIRROR 覆盖:
#   aliyun / tuna / ustc / official,或直接给一个完整基地址(如公司内网镜像)。
DOCKER_MIRROR="${DOCKER_MIRROR:-aliyun}"
resolve_docker_mirror() {
  case "$DOCKER_MIRROR" in
    official) DOCKER_MIRROR_BASE="https://download.docker.com" ;;
    aliyun)   DOCKER_MIRROR_BASE="https://mirrors.aliyun.com/docker-ce" ;;
    tuna)     DOCKER_MIRROR_BASE="https://mirrors.tuna.tsinghua.edu.cn/docker-ce" ;;
    ustc)     DOCKER_MIRROR_BASE="https://mirrors.ustc.edu.cn/docker-ce" ;;
    http://*|https://*) DOCKER_MIRROR_BASE="${DOCKER_MIRROR%/}" ;;
    *) die "未知 DOCKER_MIRROR=${DOCKER_MIRROR}（可选 aliyun/tuna/ustc/official 或完整 http(s) URL）" ;;
  esac
  log "Docker 软件仓库镜像:${DOCKER_MIRROR}（${DOCKER_MIRROR_BASE}）"
}

# 带重试地执行命令(应对下载源偶发的 SSL/连接抖动)。
# 用法：retry <次数> <间隔秒> -- <命令...>
retry() {
  local tries="$1" delay="$2"; shift 2
  [ "$1" = "--" ] && shift
  local n=1
  until "$@"; do
    if [ "$n" -ge "$tries" ]; then
      return 1
    fi
    warn "命令失败(第 ${n}/${tries} 次),${delay}s 后重试：$*"
    sleep "$delay"
    n=$((n+1))
  done
}

# ---- 探测操作系统 ----------------------------------------------------------
detect_os() {
  case "$(uname -s)" in
    Linux)  OS="linux" ;;
    Darwin) OS="darwin" ;;
    MINGW*|MSYS*|CYGWIN*)
      die "检测到 Windows：请安装 Docker Desktop：
         https://docs.docker.com/desktop/install/windows-install/" ;;
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
    [ "$(id -u)" -eq 0 ] && die "Homebrew 不能以 root 运行,请用普通用户执行。"
    return
  fi
  if [ "$(id -u)" -ne 0 ]; then
    if command -v sudo >/dev/null 2>&1; then
      SUDO="sudo"
    else
      die "需要 root 权限安装系统包,且未找到 sudo,请以 root 重试。"
    fi
  fi
}

# 解析已安装的 docker engine 版本（形如 28.4.0）
installed_version() {
  local v=""
  if command -v docker >/dev/null 2>&1; then
    v="$(docker version --format '{{.Server.Version}}' 2>/dev/null || true)"
    [ -n "$v" ] || v="$(docker --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1)"
  fi
  printf '%s' "$v"
}

# 卸载可能冲突的发行版自带旧包(官方推荐的前置清理)
remove_distro_docker_apt() {
  for p in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
    $SUDO apt-get remove -y "$p" 2>/dev/null || true
  done
}
remove_distro_docker_el() {
  local pm="$1"
  $SUDO "$pm" remove -y docker docker-client docker-client-latest docker-common \
    docker-latest docker-latest-logrotate docker-logrotate docker-engine \
    podman runc 2>/dev/null || true
}

# ---- Debian/Ubuntu：Docker 官方 APT 仓库 ----------------------------------
install_apt() {
  export DEBIAN_FRONTEND=noninteractive
  . /etc/os-release
  local distro="${ID}"          # ubuntu / debian
  local codename="${VERSION_CODENAME:-}"
  [ -n "$codename" ] || codename="$(command -v lsb_release >/dev/null 2>&1 && lsb_release -sc || true)"
  [ -n "$codename" ] || die "无法确定发行版代号（codename）,请手动配置 Docker APT 仓库"
  case "$distro" in ubuntu|debian) ;; *) distro="ubuntu" ;; esac

  log "准备 Docker APT 仓库（${distro}/${codename},镜像 ${DOCKER_MIRROR_BASE}）"
  $SUDO apt-get update -y
  $SUDO apt-get install -y ca-certificates curl gnupg
  remove_distro_docker_apt

  $SUDO install -m 0755 -d /etc/apt/keyrings
  retry 5 3 -- bash -c "curl -fsSL '${DOCKER_MIRROR_BASE}/linux/${distro}/gpg' | $SUDO gpg --batch --yes --dearmor -o /etc/apt/keyrings/docker.gpg" \
    || die "下载 Docker GPG key 失败（${DOCKER_MIRROR_BASE}）,可换 DOCKER_MIRROR=tuna/ustc 重试。"
  $SUDO chmod a+r /etc/apt/keyrings/docker.gpg

  local arch; arch="$(dpkg --print-architecture)"
  echo "deb [arch=${arch} signed-by=/etc/apt/keyrings/docker.gpg] ${DOCKER_MIRROR_BASE}/linux/${distro} ${codename} stable" \
    | $SUDO tee /etc/apt/sources.list.d/docker.list >/dev/null
  $SUDO apt-get update -y

  log "apt-get 安装最新版 docker-ce + compose 插件 ..."
  retry 5 5 -- $SUDO apt-get install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin \
    || die "docker-ce 安装多次失败,请检查到 download.docker.com 的网络连通性后重试。"
  SERVICE="docker"
}

# ---- RHEL 系(dnf/yum)：Docker 官方 YUM 仓库 -------------------------------
install_el() {
  local pm="$1"
  remove_distro_docker_el "$pm"

  # 直接写仓库文件,baseurl/gpgkey 指向所选镜像(默认阿里云),避免依赖 config-manager,
  # 也避免官方 docker-ce.repo 里写死的 download.docker.com 在国内被重置。
  log "写入 Docker YUM 仓库（镜像 ${DOCKER_MIRROR_BASE}）..."
  $SUDO tee /etc/yum.repos.d/docker-ce.repo >/dev/null <<EOF
[docker-ce-stable]
name=Docker CE Stable - \$basearch
baseurl=${DOCKER_MIRROR_BASE}/linux/centos/\$releasever/\$basearch/stable
enabled=1
gpgcheck=1
gpgkey=${DOCKER_MIRROR_BASE}/linux/centos/gpg
EOF

  log "${pm} 安装最新版 docker-ce + compose 插件 ..."
  retry 5 5 -- $SUDO "$pm" install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin \
    || die "docker-ce 安装多次失败,请检查到 download.docker.com 的网络连通性后重试。"
  SERVICE="docker"
}

# ---- macOS：Homebrew Cask（Docker Desktop,滚动最新版）--------------------
install_brew() {
  log "brew 安装 Docker Desktop（Homebrew Cask,滚动最新版,含 compose）..."
  brew install --cask docker
  warn "请从菜单栏启动 Docker Desktop 以拉起引擎；启动后可用 docker version 校验。"
}

# ---- 启动 docker 服务并设置开机自启 --------------------------------------
start_service() {
  [ "$START" = "1" ] || { log "START=0,跳过启动/开机自启"; return; }
  if [ "$PM" = "brew" ]; then
    log "macOS 请手动启动 Docker Desktop 应用（首次需在图形界面授权）。"
    return
  fi
  if command -v systemctl >/dev/null 2>&1; then
    log "systemctl enable --now ${SERVICE} ..."
    $SUDO systemctl enable --now "$SERVICE" \
      || warn "启动失败,可稍后手动执行：sudo systemctl enable --now ${SERVICE}"
  else
    log "无 systemd（如容器）：尝试 service ${SERVICE} start ..."
    $SUDO service "$SERVICE" start 2>/dev/null \
      || warn "未检测到 init 系统,可手动执行 dockerd & 或在具备 systemd 的宿主机上运行。"
  fi
}

# ---- 可选：把指定用户加入 docker 组（免 sudo 用 docker）------------------
add_docker_group() {
  [ -n "${DOCKER_ADD_USER:-}" ] || return 0
  [ "$PM" = "brew" ] && return 0
  if id "$DOCKER_ADD_USER" >/dev/null 2>&1; then
    log "将用户 ${DOCKER_ADD_USER} 加入 docker 组（需重新登录生效）..."
    $SUDO groupadd -f docker || true
    $SUDO usermod -aG docker "$DOCKER_ADD_USER" || warn "加入 docker 组失败,请手动处理。"
  else
    warn "用户 ${DOCKER_ADD_USER} 不存在,跳过加组。"
  fi
}

# ---- 配置国内镜像加速（写 /etc/docker/daemon.json 的 registry-mirrors）-----
# 默认从 Docker Hub 拉镜像常因网络不通而失败,这里写入国内镜像源避免拉取失败。
configure_registry_mirrors() {
  # brew(Docker Desktop)用图形界面配置,daemon.json 路径不同,跳过。
  [ "$PM" = "brew" ] && return 0
  # 显式清空则不配置。
  [ -n "${REGISTRY_MIRRORS// /}" ] || { log "REGISTRY_MIRRORS 为空,跳过镜像加速配置"; return 0; }

  # 把空格分隔的地址转成 JSON 数组元素:"a",\n    "b"
  local json_items="" m
  for m in $REGISTRY_MIRRORS; do
    [ -n "$m" ] || continue
    if [ -z "$json_items" ]; then
      json_items="    \"$m\""
    else
      json_items="${json_items},
    \"$m\""
    fi
  done

  local dir="/etc/docker" file="/etc/docker/daemon.json"
  $SUDO install -m 0755 -d "$dir"

  if [ -f "$file" ] && ! grep -q '"registry-mirrors"' "$file" 2>/dev/null; then
    # 已有 daemon.json 但无 registry-mirrors 字段:不覆盖用户配置,仅提示。
    warn "已存在 ${file} 且不含 registry-mirrors,为避免覆盖你的配置,跳过自动写入。"
    warn "请手动在其中加入:\"registry-mirrors\": [ ${REGISTRY_MIRRORS// /, } ]"
    return 0
  fi
  if [ -f "$file" ]; then
    $SUDO cp -a "$file" "${file}.bak.$$" 2>/dev/null || true
    log "已备份原 daemon.json 到 ${file}.bak.$$"
  fi

  log "写入镜像加速到 ${file}:${REGISTRY_MIRRORS}"
  printf '{\n  "registry-mirrors": [\n%s\n  ]\n}\n' "$json_items" | $SUDO tee "$file" >/dev/null

  # START=0 时只写配置、不触碰服务(与 start_service 的语义保持一致)。
  if [ "$START" != "1" ]; then
    log "START=0,已写入镜像加速配置,未重启 docker;下次启动即生效。"
    return 0
  fi
  # 让配置生效:优先 systemd 重启,否则提示手动重启。
  if command -v systemctl >/dev/null 2>&1; then
    $SUDO systemctl restart "$SERVICE" \
      || warn "重启 ${SERVICE} 失败,请手动执行:sudo systemctl restart ${SERVICE}"
  else
    warn "无 systemd,请手动重启 docker 使镜像加速生效。"
  fi
}

# ---- 主流程 ----------------------------------------------------------------
detect_os
detect_pm
setup_privilege

log "经由 ${PM} 安装最新版 Docker（含 compose v2 插件）"

# 解析 docker-ce 软件仓库镜像（brew 用 Docker Desktop,不需要）。
[ "$PM" = "brew" ] || resolve_docker_mirror

case "$PM" in
  apt)  install_apt ;;
  dnf)  install_el dnf ;;
  yum)  install_el yum ;;
  brew) install_brew ;;
esac

start_service
add_docker_group
configure_registry_mirrors

# ---- 验证 ------------------------------------------------------------------
if [ "$PM" = "brew" ]; then
  log "安装完成：Docker Desktop（请启动应用后运行 docker version 校验）"
  exit 0
fi

# 客户端版本(不依赖引擎启动),用于确认包已装上
cli_ver="$(docker --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1 || true)"
[ -n "$cli_ver" ] || die "安装后未找到可用的 docker 客户端"

got="$(installed_version)"
if [ -n "$got" ]; then
  log "版本:Docker Engine ${got}(引擎已就绪)"
else
  warn "未能获取 Docker Server 版本（引擎可能未启动,如在无 systemd 的容器内属正常）"
  log "已安装 docker 客户端 ${cli_ver}"
fi

# compose 插件版本
if docker compose version >/dev/null 2>&1; then
  log "compose 插件：$(docker compose version 2>/dev/null | head -n1)"
else
  warn "未检测到 docker compose 插件,请检查 docker-compose-plugin 是否安装成功。"
fi

log "安装完成：Docker ${got:-$cli_ver}（$(command -v docker)）+ docker compose"
log "连通性自检：docker run --rm hello-world"
