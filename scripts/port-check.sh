#!/usr/bin/env bash
#
# port-check.sh — 查端口占用 / 批量杀进程
#
# 支持系统：Linux（ss/lsof）/ macOS（lsof）
#
# 三个子命令：
#   list   列出本机所有正在监听的端口（端口 / 协议 / PID / 用户 / 命令）
#   check  查看某端口被谁占用（PID / 进程名 / 用户）
#   kill   杀掉占用某端口的所有进程（默认 TERM，可 -9 强杀；先确认再动手）
#
# 用法：
#   ./port-check.sh list                      # 列出所有监听端口
#   ./port-check.sh list -u                    # 同时列出 UDP 端口
#   ./port-check.sh check 8080                # 查 8080 端口占用
#   ./port-check.sh check 80 443 3306         # 一次查多个端口
#   ./port-check.sh kill 8080                 # 杀掉占用 8080 的进程（发 SIGTERM）
#   ./port-check.sh kill -9 8080              # 强杀（SIGKILL）
#   ./port-check.sh kill -y 8080 9090         # 跳过确认，批量杀多个端口
#
set -euo pipefail

GREEN=$'\033[0;32m'; YELLOW=$'\033[0;33m'; RED=$'\033[0;31m'; BOLD=$'\033[1m'; RESET=$'\033[0m'
log()  { printf '%s[port]%s %s\n' "$GREEN" "$RESET" "$*"; }
warn() { printf '%s[port]%s %s\n' "$YELLOW" "$RESET" "$*" >&2; }
die()  { printf '%s[port]%s %s\n' "$RED" "$RESET" "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
用法：
  port-check.sh list  [-u]                     列出本机所有监听端口
  port-check.sh check <端口> [端口...]        查看端口占用
  port-check.sh kill  [-9] [-y] <端口> [端口...]  杀掉占用端口的进程

选项（list）：
  -u   同时列出 UDP 端口（默认仅 TCP LISTEN）

选项（kill）：
  -9   使用 SIGKILL 强杀（默认 SIGTERM 优雅退出）
  -y   跳过交互确认，直接杀
EOF
}

# ---- 找出占用某端口的 PID（去重）------------------------------------------
# 输出：每行一个 PID；无占用则无输出。
pids_on_port() {
  local port="$1"
  # 注：脚本开启了 pipefail，lsof/grep 在「无匹配」时会返回非 0，
  #     属正常结果（端口空闲），故用 || true 吞掉，避免误触 set -e。
  if command -v lsof >/dev/null 2>&1; then
    { lsof -nP -iTCP:"$port" -sTCP:LISTEN -t 2>/dev/null || true; } | sort -u
  elif command -v ss >/dev/null 2>&1; then
    # 从 ss 的 users:(("proc",pid=1234,fd=7)) 里抠出 pid
    { ss -ltnp 2>/dev/null | grep -E "[:.]$port\b" || true; } \
      | grep -oE 'pid=[0-9]+' | cut -d= -f2 | sort -u || true
  else
    die "未找到 lsof 或 ss，无法查询端口占用"
  fi
}

# ---- 打印某 PID 的可读信息 -------------------------------------------------
proc_info() {
  local pid="$1"
  # comm=进程名 user=属主；ps 在 Linux/macOS 上通用
  ps -o pid=,user=,comm= -p "$pid" 2>/dev/null | awk '{$1=$1};1'
}

# ---- 枚举所有监听中的套接字 ------------------------------------------------
# 输出：每行 "PROTO PORT PID"（PID 不可知时为 -）。$1=1 时含 UDP。
listening_entries() {
  local with_udp="$1"
  if command -v lsof >/dev/null 2>&1; then
    local sel=(-nP -iTCP -sTCP:LISTEN)
    [ "$with_udp" = "1" ] && sel+=(-iUDP)
    { lsof "${sel[@]}" 2>/dev/null || true; } | awk '
      NR>1 {
        cmd=$1; pid=$2; proto=""; addr="";
        for (i=4; i<=NF; i++) if ($i=="TCP" || $i=="UDP") { proto=$i; addr=$(i+1); break }
        if (proto=="") next;
        n=split(addr, p, ":"); port=p[n];
        if (port ~ /^[0-9]+$/) print proto, port, pid;
      }'
  elif command -v ss >/dev/null 2>&1; then
    _ss_dump() { # $1=t|u  $2=PROTO 标签
      { ss "-${1}lnpH" 2>/dev/null || true; } | awk -v proto="$2" '
        {
          n=split($4, a, ":"); port=a[n]; pid="-";
          if (match($0, /pid=[0-9]+/)) pid=substr($0, RSTART+4, RLENGTH-4);
          if (port ~ /^[0-9]+$/) print proto, port, pid;
        }'
    }
    _ss_dump t TCP
    [ "$with_udp" = "1" ] && _ss_dump u UDP
  else
    die "未找到 lsof 或 ss，无法枚举监听端口"
  fi
}

cmd_list() {
  local with_udp=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -u|--udp) with_udp=1; shift ;;
      -h|--help) usage; exit 0 ;;
      *) die "list 不支持的参数：$1" ;;
    esac
  done

  local entries; entries="$(listening_entries "$with_udp" | sort -u -k2,2n -k1,1)"
  if [ -z "$entries" ]; then
    log "没有监听中的端口"
    return 0
  fi

  printf '%s%-5s %-7s %-8s %-14s %s%s\n' "$BOLD" "PROTO" "PORT" "PID" "USER" "COMMAND" "$RESET"
  local proto port pid user comm
  while read -r proto port pid; do
    [ -n "$port" ] || continue
    if [ -z "$pid" ] || [ "$pid" = "-" ]; then
      user="-"; comm="-"
    else
      user="$(ps -o user= -p "$pid" 2>/dev/null | awk '{$1=$1};1')"
      comm="$(ps -o comm= -p "$pid" 2>/dev/null | awk '{$1=$1};1')"
      [ -n "$user" ] || user="-"
      [ -n "$comm" ] || comm="-"
    fi
    printf '%-5s %-7s %-8s %-14s %s\n' "$proto" "$port" "$pid" "$user" "$comm"
  done <<<"$entries"
}

cmd_check() {
  [ "$#" -ge 1 ] || { usage; exit 1; }
  local port found_any=0
  for port in "$@"; do
    printf '%s== 端口 %s ==%s\n' "$BOLD" "$port" "$RESET"
    local pids; pids="$(pids_on_port "$port")"
    if [ -z "$pids" ]; then
      printf '  %s空闲（无进程监听）%s\n' "$GREEN" "$RESET"
      continue
    fi
    found_any=1
    printf '  %-8s %-12s %s\n' "PID" "USER" "COMMAND"
    local pid
    while read -r pid; do
      [ -n "$pid" ] || continue
      local info; info="$(proc_info "$pid")"
      printf '  %s\n' "${info:-$pid  (进程信息不可读)}"
    done <<<"$pids"
  done
  return $((found_any ? 0 : 0))
}

cmd_kill() {
  local sig="TERM" assume_yes=0
  # 解析选项（允许出现在端口前）
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -9)      sig="KILL"; shift ;;
      -y|--yes) assume_yes=1; shift ;;
      -h|--help) usage; exit 0 ;;
      --) shift; break ;;
      -*) die "未知选项：$1" ;;
      *) break ;;
    esac
  done
  [ "$#" -ge 1 ] || { usage; exit 1; }

  local port total=0
  for port in "$@"; do
    local pids; pids="$(pids_on_port "$port")"
    if [ -z "$pids" ]; then
      warn "端口 $port 无进程占用，跳过"
      continue
    fi

    printf '%s== 端口 %s 将被杀掉的进程（信号 SIG%s）==%s\n' "$BOLD" "$port" "$sig" "$RESET"
    local pid
    while read -r pid; do
      [ -n "$pid" ] || continue
      printf '  %s\n' "$(proc_info "$pid")"
    done <<<"$pids"

    if [ "$assume_yes" -ne 1 ]; then
      printf '确认杀掉以上进程？[y/N] '
      local ans; read -r ans || ans=""
      case "$ans" in
        y|Y|yes|YES) ;;
        *) warn "已取消端口 $port 的操作"; continue ;;
      esac
    fi

    while read -r pid; do
      [ -n "$pid" ] || continue
      if kill -s "$sig" "$pid" 2>/dev/null; then
        log "已向 PID $pid 发送 SIG$sig"
        total=$((total + 1))
      else
        warn "无法杀掉 PID ${pid}（可能已退出或权限不足，试试 sudo）"
      fi
    done <<<"$pids"
  done
  log "完成，共发送 $total 个信号"
}

# ---- 入口 ------------------------------------------------------------------
main() {
  [ "$#" -ge 1 ] || { usage; exit 1; }
  local sub="$1"; shift
  case "$sub" in
    list)       cmd_list  "$@" ;;
    check)      cmd_check "$@" ;;
    kill)       cmd_kill  "$@" ;;
    -h|--help|help) usage ;;
    *) die "未知子命令：${sub}（可用：check / kill）" ;;
  esac
}

main "$@"
