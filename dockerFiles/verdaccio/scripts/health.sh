#!/usr/bin/env bash
#
# health.sh — 查看/管理本 compose 组件的容器状态
#
# 通用脚本：放在 <组件>/scripts/ 下，自动定位组件目录，无需按组件改动。
#
# 子命令：
#   status   (默认) 查看各容器运行状态与健康检查
#   start           拉起容器(compose up -d)
#   stop            停止容器(compose stop)
#   restart         重启容器(compose restart)
#
# 用法：
#   ./health.sh            # 等同 ./health.sh status
#   ./health.sh start
#   ./health.sh stop
#   ./health.sh restart
#
set -euo pipefail

GREEN=$'\033[0;32m'; YELLOW=$'\033[0;33m'; RED=$'\033[0;31m'; BOLD=$'\033[1m'; RESET=$'\033[0m'
log()  { printf '%s[health]%s %s\n' "$GREEN" "$RESET" "$*"; }
warn() { printf '%s[health]%s %s\n' "$YELLOW" "$RESET" "$*" >&2; }
die()  { printf '%s[health]%s %s\n' "$RED" "$RESET" "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
用法：
  health.sh [status]     查看容器状态与健康检查(默认)
  health.sh start        拉起容器(compose up -d)
  health.sh stop         停止容器(compose stop)
  health.sh restart      重启容器(compose restart)
EOF
}

case "${1:-}" in -h|--help|help) usage; exit 0 ;; esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMP_DIR="$(dirname "$SCRIPT_DIR")"
COMP_NAME="$(basename "$COMP_DIR")"

# ---- 探测 compose ----------------------------------------------------------
command -v docker >/dev/null 2>&1 || die "未找到 docker,无法管理容器。"
if docker compose version >/dev/null 2>&1; then COMPOSE="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then COMPOSE="docker-compose"
else die "未找到 docker compose / docker-compose。"; fi
docker info >/dev/null 2>&1 || die "无法连接 Docker 守护进程,请先启动 Docker。"

[ -f "$COMP_DIR/docker-compose.yml" ] || [ -f "$COMP_DIR/compose.yml" ] \
  || die "组件目录缺少 compose 文件:$COMP_DIR"

# ---- 子命令 ----------------------------------------------------------------
cmd_status() {
  printf '%s组件「%s」容器状态:%s\n' "$BOLD" "$COMP_NAME" "$RESET"
  # -a 连同已停止的服务一起列出,便于看清整栈
  ( cd "$COMP_DIR" && $COMPOSE ps -a )
}

cmd_start() {
  log "拉起「${COMP_NAME}」…"
  ( cd "$COMP_DIR" && $COMPOSE up -d )
  cmd_status
}

cmd_stop() {
  log "停止「${COMP_NAME}」…"
  ( cd "$COMP_DIR" && $COMPOSE stop )
  cmd_status
}

cmd_restart() {
  log "重启「${COMP_NAME}」…"
  ( cd "$COMP_DIR" && $COMPOSE restart )
  cmd_status
}

# ---- 入口 ------------------------------------------------------------------
sub="${1:-status}"
case "$sub" in
  status)          cmd_status ;;
  start|up)        cmd_start ;;
  stop)            cmd_stop ;;
  restart)         cmd_restart ;;
  *) die "未知子命令:${sub}(可用:status / start / stop / restart)" ;;
esac
