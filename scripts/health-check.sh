#!/usr/bin/env bash
#
# health-check.sh — 主机健康巡检（磁盘 / 内存 / 负载 / 关键服务端口）
#
# 支持系统：Linux（Ubuntu/Debian/RHEL 系）/ macOS
#
# 输出四段体检报告，任意一项超过阈值会以 [WARN] 标红，
# 全部脚本以「是否存在告警」决定退出码（0=健康，1=有告警），便于接监控/定时任务。
#
# 用法：
#   ./health-check.sh                      # 用默认阈值巡检
#   DISK_WARN=90 MEM_WARN=90 ./health-check.sh   # 自定义磁盘/内存告警百分比
#   LOAD_WARN=8 ./health-check.sh          # 自定义 1 分钟负载告警阈值（默认=CPU 核数）
#   PORTS="22 80 443 3306" ./health-check.sh     # 自定义要检查的关键端口
#
set -euo pipefail

# ---- 阈值（可用环境变量覆盖）----------------------------------------------
DISK_WARN="${DISK_WARN:-85}"     # 磁盘使用率百分比告警线
MEM_WARN="${MEM_WARN:-85}"       # 内存使用率百分比告警线
LOAD_WARN="${LOAD_WARN:-}"       # 1 分钟平均负载告警线（空则取 CPU 核数）
PORTS="${PORTS:-22 80 443}"      # 关键服务端口列表（空格分隔）

# ---- 输出辅助 --------------------------------------------------------------
BOLD=$'\033[1m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[0;33m'; RED=$'\033[0;31m'; RESET=$'\033[0m'
WARN_COUNT=0

title() { printf '\n%s== %s ==%s\n' "$BOLD" "$*" "$RESET"; }
ok()    { printf '  %s[ OK ]%s %s\n' "$GREEN" "$RESET" "$*"; }
warn()  { printf '  %s[WARN]%s %s\n' "$YELLOW" "$RESET" "$*"; WARN_COUNT=$((WARN_COUNT + 1)); }
info()  { printf '  %s\n' "$*"; }

# ---- 探测操作系统 ----------------------------------------------------------
case "$(uname -s)" in
  Linux)  OS="linux" ;;
  Darwin) OS="darwin" ;;
  *) OS="other" ;;
esac

# ---- CPU 核数（用于负载阈值）----------------------------------------------
cpu_cores() {
  if [ "$OS" = "darwin" ]; then sysctl -n hw.ncpu 2>/dev/null || echo 1
  elif command -v nproc >/dev/null 2>&1; then nproc
  else grep -c ^processor /proc/cpuinfo 2>/dev/null || echo 1; fi
}
CORES="$(cpu_cores)"
[ -z "$LOAD_WARN" ] && LOAD_WARN="$CORES"

# ---- 1. 磁盘 ---------------------------------------------------------------
# 说明：磁盘检查用 while 逐行读取，为让 WARN_COUNT 能在主 shell 累加，
#       实现放在 main() 里用进程替换喂给 while（管道会开子 shell，累加会丢失）。

# ---- 2. 内存 ---------------------------------------------------------------
check_mem() {
  title "内存使用率（阈值 ${MEM_WARN}%）"
  if [ "$OS" = "darwin" ]; then
    local total_b used_pct page_size free spec active wired
    total_b=$(sysctl -n hw.memsize)
    page_size=$(sysctl -n hw.pagesize)
    # 从 vm_stat 估算已用（active + wired + compressed）
    local stats; stats=$(vm_stat)
    local pg_active pg_wired pg_comp
    pg_active=$(printf '%s\n' "$stats" | awk '/Pages active/    {gsub("\\.","",$3); print $3}')
    pg_wired=$( printf '%s\n' "$stats" | awk '/Pages wired/     {gsub("\\.","",$4); print $4}')
    pg_comp=$(  printf '%s\n' "$stats" | awk '/occupied by comp/{gsub("\\.","",$5); print $5}')
    local used_b=$(( (pg_active + pg_wired + pg_comp) * page_size ))
    used_pct=$(( used_b * 100 / total_b ))
    local total_h; total_h=$(( total_b / 1024 / 1024 ))
    local used_h; used_h=$(( used_b / 1024 / 1024 ))
    local line; line=$(printf '已用 %d/%d MiB (%d%%)' "$used_h" "$total_h" "$used_pct")
    if [ "$used_pct" -ge "$MEM_WARN" ]; then warn "$line"; else ok "$line"; fi
  else
    # Linux：优先用 free 的 available 计算真实使用率
    if command -v free >/dev/null 2>&1; then
      read -r total used_pct line < <(free -m | awk '/^Mem:/ {
        avail=($7==""?$4:$7); used=$2-avail; pct=int(used*100/$2);
        printf "%d %d 已用 %d/%d MiB (%d%%)", $2, pct, used, $2, pct }')
      if [ "$used_pct" -ge "$MEM_WARN" ]; then warn "$line"; else ok "$line"; fi
    else
      info "未找到 free 命令，跳过内存检查"
    fi
  fi
}

# ---- 3. 负载 ---------------------------------------------------------------
check_load() {
  title "系统负载（1 分钟阈值 ${LOAD_WARN}，CPU 核数 ${CORES}）"
  local load1 load5 load15
  if [ "$OS" = "darwin" ]; then
    read -r load1 load5 load15 < <(sysctl -n vm.loadavg | awk '{print $2, $3, $4}')
  else
    read -r load1 load5 load15 _ < /proc/loadavg
  fi
  local line; line=$(printf '1m=%s  5m=%s  15m=%s' "$load1" "$load5" "$load15")
  # 用 awk 做浮点比较
  if awk "BEGIN{exit !($load1 >= $LOAD_WARN)}"; then warn "$line"; else ok "$line"; fi
}

# ---- 4. 关键服务端口 -------------------------------------------------------
port_listening() {
  local port="$1"
  if command -v ss >/dev/null 2>&1; then
    ss -ltn 2>/dev/null | awk '{print $4}' | grep -qE "[:.]$port\$"
  elif command -v lsof >/dev/null 2>&1; then
    lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1
  elif command -v netstat >/dev/null 2>&1; then
    netstat -an 2>/dev/null | grep -E 'LISTEN' | awk '{print $4}' | grep -qE "[:.]$port\$"
  else
    return 2
  fi
}

check_ports() {
  title "关键服务端口（${PORTS}）"
  local port
  for port in $PORTS; do
    if port_listening "$port"; then
      ok "端口 $port 正在监听"
    else
      case $? in
        2) info "无 ss/lsof/netstat 可用，跳过端口检查"; return 0 ;;
        *) warn "端口 $port 未监听" ;;
      esac
    fi
  done
}

# ---- 汇总统计告警数（子 shell 里的 while 无法累加，改为逐项在主 shell 执行）
main() {
  printf '%s主机健康巡检%s  —  %s  —  %s\n' "$BOLD" "$RESET" "$(hostname)" "$(date '+%F %T')"

  # check_disk 内的 while 在管道子 shell，无法回传 WARN_COUNT；改用进程替换
  title "磁盘使用率（阈值 ${DISK_WARN}%）"
  while read -r fs blocks used avail pct mount; do
    case "$fs" in tmpfs|devtmpfs|devfs|map*|none|overlay) continue ;; esac
    use="${pct%\%}"
    line=$(printf '%-24s %5s 已用  挂载于 %s' "$fs" "$pct" "$mount")
    if [ "${use:-0}" -ge "$DISK_WARN" ]; then warn "$line"; else ok "$line"; fi
  done < <(df -P -k 2>/dev/null | awk 'NR>1')

  check_mem
  check_load
  check_ports

  printf '\n'
  if [ "$WARN_COUNT" -eq 0 ]; then
    printf '%s巡检完成：全部正常%s\n' "$GREEN" "$RESET"
    exit 0
  else
    printf '%s巡检完成：发现 %d 项告警%s\n' "$RED" "$WARN_COUNT" "$RESET"
    exit 1
  fi
}

main "$@"
