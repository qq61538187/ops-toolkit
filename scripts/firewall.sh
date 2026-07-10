#!/usr/bin/env bash
#
# firewall.sh — 防火墙端口放行管理（查看 / 批量放行 / 批量关闭）
#
# 支持系统：Linux（自动探测 firewalld / ufw）
#           RHEL/Rocky/CentOS 通常是 firewalld，Ubuntu/Debian 通常是 ufw。
#           macOS 无端口级防火墙（应用层防火墙请用系统设置），脚本会优雅报错退出。
#
# 端口写法（spec）：
#   80            省略协议按 tcp
#   443/tcp       指定协议
#   53/udp        UDP
#   8000-8100/tcp 端口范围
#
# 三个子命令：
#   list                  查看当前放行的端口/服务
#   allow <spec> [...]    批量放行（直接执行）
#   deny  [-y] <spec> [...]  批量关闭（先列清单再确认，-y 跳过确认；close 为别名）
#
# 用法：
#   ./firewall.sh list
#   ./firewall.sh allow 80 443/tcp 53/udp
#   ./firewall.sh allow 8000-8100/tcp
#   ./firewall.sh deny 8080 9090
#   ./firewall.sh deny -y 8080 9090
#
set -euo pipefail

GREEN=$'\033[0;32m'; YELLOW=$'\033[0;33m'; RED=$'\033[0;31m'; BOLD=$'\033[1m'; RESET=$'\033[0m'
log()  { printf '%s[fw]%s %s\n' "$GREEN" "$RESET" "$*"; }
warn() { printf '%s[fw]%s %s\n' "$YELLOW" "$RESET" "$*" >&2; }
die()  { printf '%s[fw]%s %s\n' "$RED" "$RESET" "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
用法：
  firewall.sh list                       查看当前放行的端口/服务
  firewall.sh allow <spec> [spec...]     批量放行
  firewall.sh deny  [-y] <spec> [spec...]  批量关闭（close 为别名）

spec 写法：
  80            省略协议按 tcp
  443/tcp       指定协议
  53/udp        UDP
  8000-8100/tcp 端口范围

选项（deny）：
  -y   跳过交互确认，直接关闭
EOF
}

# ---- 探测操作系统 ----------------------------------------------------------
detect_os() {
  case "$(uname -s)" in
    Linux) : ;;
    Darwin) die "本脚本仅支持 Linux 端口防火墙（firewalld/ufw）。macOS 请用「系统设置 → 网络 → 防火墙」（应用层防火墙）。" ;;
    *) die "不支持的操作系统：$(uname -s)" ;;
  esac
}

# ---- 探测后端 --------------------------------------------------------------
# firewalld 需守护进程 running 才算可用；否则退回 ufw。
detect_backend() {
  if command -v firewall-cmd >/dev/null 2>&1 \
     && firewall-cmd --state >/dev/null 2>&1; then
    BACKEND="firewalld"
  elif command -v ufw >/dev/null 2>&1; then
    BACKEND="ufw"
  elif command -v firewall-cmd >/dev/null 2>&1; then
    die "检测到 firewalld 但守护进程未运行，请先：$SUDO systemctl start firewalld"
  else
    die "未找到受支持的防火墙后端（firewalld / ufw），请先安装并启用其一。"
  fi
}

# ---- root / sudo -----------------------------------------------------------
setup_privilege() {
  SUDO=""
  if [ "$(id -u)" -ne 0 ]; then
    if command -v sudo >/dev/null 2>&1; then
      SUDO="sudo"
    else
      die "需要 root 权限操作防火墙，且未找到 sudo，请以 root 重试。"
    fi
  fi
}

# ---- 解析端口 spec ---------------------------------------------------------
# 入参：一个 spec（如 80 / 443/tcp / 8000-8100/udp）
# 出参：全局 PORT（单端口或 N-M 范围）与 PROTO（tcp/udp，缺省 tcp）
normalize_spec() {
  local spec="$1" proto="tcp" port
  if [[ "$spec" == */* ]]; then
    proto="${spec##*/}"
    port="${spec%%/*}"
  else
    port="$spec"
  fi
  case "$proto" in
    tcp|udp) ;;
    *) die "非法协议：$proto（spec=$spec，仅支持 tcp/udp）" ;;
  esac
  if [[ "$port" =~ ^[0-9]+$ ]]; then
    [ "$port" -ge 1 ] && [ "$port" -le 65535 ] || die "端口越界：$port（spec=$spec）"
  elif [[ "$port" =~ ^[0-9]+-[0-9]+$ ]]; then
    local lo="${port%-*}" hi="${port#*-}"
    { [ "$lo" -ge 1 ] && [ "$hi" -le 65535 ] && [ "$lo" -lt "$hi" ]; } \
      || die "端口范围非法：$port（spec=$spec）"
  else
    die "非法端口：$port（spec=$spec，应为数字或 N-M 范围）"
  fi
  PORT="$port"; PROTO="$proto"
}

# ---- 后端底层动作 ----------------------------------------------------------
# firewalld 用 --add-port/--remove-port（范围写作 N-M）；ufw 范围写作 N:M。
fw_list() {
  if [ "$BACKEND" = "firewalld" ]; then
    local zone; zone="$(firewall-cmd --get-default-zone 2>/dev/null || echo '?')"
    printf '%s后端：firewalld（默认 zone：%s）%s\n' "$BOLD" "$zone" "$RESET"
    printf '  端口：%s\n'   "$( { firewall-cmd --list-ports        2>/dev/null || true; } )"
    printf '  服务：%s\n'   "$( { firewall-cmd --list-services     2>/dev/null || true; } )"
    local rich; rich="$( { firewall-cmd --list-rich-rules 2>/dev/null || true; } )"
    [ -n "$rich" ] && printf '  富规则：\n%s\n' "$rich"
  else
    printf '%s后端：ufw%s\n' "$BOLD" "$RESET"
    { $SUDO ufw status verbose 2>/dev/null || true; } | sed 's/^/  /'
  fi
}

# ufw 端口写法：单端口原样，范围 N-M → N:M
ufw_port() {
  printf '%s' "${1/-/:}"
}

fw_allow_one() { # PORT PROTO
  if [ "$BACKEND" = "firewalld" ]; then
    $SUDO firewall-cmd --permanent --add-port="$1/$2" >/dev/null
  else
    $SUDO ufw allow "$(ufw_port "$1")/$2" >/dev/null
  fi
}

fw_deny_one() { # PORT PROTO
  if [ "$BACKEND" = "firewalld" ]; then
    $SUDO firewall-cmd --permanent --remove-port="$1/$2" >/dev/null
  else
    $SUDO ufw delete allow "$(ufw_port "$1")/$2" >/dev/null
  fi
}

fw_reload() {
  if [ "$BACKEND" = "firewalld" ]; then
    $SUDO firewall-cmd --reload >/dev/null && log "firewalld 已重载（规则已持久化）"
  fi
  # ufw 的 allow/delete 立即生效且持久化，无需 reload
}

# ---- 子命令 ----------------------------------------------------------------
cmd_list() {
  fw_list
}

cmd_allow() {
  [ "$#" -ge 1 ] || { usage; exit 1; }
  local spec ok=0
  for spec in "$@"; do
    normalize_spec "$spec"
    if fw_allow_one "$PORT" "$PROTO"; then
      log "放行 $PORT/$PROTO"
      ok=$((ok + 1))
    else
      warn "放行失败：$PORT/$PROTO"
    fi
  done
  [ "$ok" -gt 0 ] && fw_reload
  log "完成，共放行 $ok 条"
}

cmd_deny() {
  local assume_yes=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -y|--yes) assume_yes=1; shift ;;
      -h|--help) usage; exit 0 ;;
      --) shift; break ;;
      -*) die "未知选项：$1" ;;
      *) break ;;
    esac
  done
  [ "$#" -ge 1 ] || { usage; exit 1; }

  # 先全部 normalize（含校验），收集成待关闭清单
  local spec specs=()
  for spec in "$@"; do
    normalize_spec "$spec"
    specs+=("$PORT/$PROTO")
  done

  printf '%s即将关闭以下放行（后端：%s）：%s\n' "$BOLD" "$BACKEND" "$RESET"
  local s
  for s in "${specs[@]}"; do printf '  - %s\n' "$s"; done

  if [ "$assume_yes" -ne 1 ]; then
    printf '确认关闭？此操作可能影响正在使用该端口的连接（如误关 SSH 会断开）。[y/N] '
    local ans; read -r ans || ans=""
    case "$ans" in
      y|Y|yes|YES) ;;
      *) warn "已取消"; return 0 ;;
    esac
  fi

  local ok=0 item port proto
  for item in "${specs[@]}"; do
    port="${item%%/*}"; proto="${item##*/}"
    if fw_deny_one "$port" "$proto"; then
      log "关闭 $item"
      ok=$((ok + 1))
    else
      warn "关闭失败或规则不存在：$item"
    fi
  done
  [ "$ok" -gt 0 ] && fw_reload
  log "完成，共关闭 $ok 条"
}

# ---- 入口 ------------------------------------------------------------------
main() {
  [ "$#" -ge 1 ] || { usage; exit 1; }
  local sub="$1"; shift

  case "$sub" in
    -h|--help|help) usage; exit 0 ;;
  esac

  detect_os
  setup_privilege
  detect_backend

  case "$sub" in
    list)        cmd_list  "$@" ;;
    allow|add)   cmd_allow "$@" ;;
    deny|close)  cmd_deny  "$@" ;;
    *) die "未知子命令：${sub}（可用：list / allow / deny）" ;;
  esac
}

main "$@"
