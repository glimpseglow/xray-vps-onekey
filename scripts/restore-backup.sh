#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_NAME="xray-vps-onekey"
BACKUP_DIR="/etc/${PROJECT_NAME}/backups"

usage() {
  cat <<USAGE
${PROJECT_NAME} 配置回滚

用法:
  bash scripts/restore-backup.sh                # 列出快照并选择一个回滚
  bash scripts/restore-backup.sh <快照.tar.gz>   # 回滚指定快照
  bash scripts/restore-backup.sh --list         # 列出可用快照
  bash scripts/restore-backup.sh --help         # 显示此帮助

快照保存在 ${BACKUP_DIR}/，命名为 pre-install-YYYYmmdd-HHMMSS.tar.gz。
此操作会用快照内容覆盖当前配置，请确认后再执行。
USAGE
}

list_snapshots() {
  echo "可用快照（${BACKUP_DIR}）:"
  local found=0
  for f in "${BACKUP_DIR}"/pre-install-*.tar.gz; do
    [[ -f "$f" ]] || continue
    printf '  %s\t(%s 字节)\n' "$(basename "$f")" "$(stat -c '%s' "$f" 2>/dev/null || stat -f '%z' "$f" 2>/dev/null)"
    found=1
  done
  [[ $found -eq 0 ]] && echo "  (无)" || true
}

extract_snapshot() {
  local snap="$1"
  local work
  work="$(mktemp -d)"
  tar -xzf "$snap" -C "$work"
  echo "$work"
}

restore_snapshot() {
  local snap="$1"
  [[ -f "$snap" ]] || { echo "快照不存在: $snap"; exit 1; }

  local work extracted
  work="$(extract_snapshot "$snap")"
  extracted="${work}/$(basename "${snap%.tar.gz}")"

  echo "快照内容:"
  ( cd "$extracted" && find . -maxdepth 2 -print | sort )
  echo

  echo "此操作将用快照覆盖当前配置并重载服务。"
  read -r -p "确认继续？[y/N] " ans
  case "$ans" in
    y|Y|yes|YES) ;;
    *) echo "已取消。"; rm -rf "$work"; exit 0 ;;
  esac

  cp -a "${extracted}/etc/ssh/." /etc/ssh/ 2>/dev/null || true
  cp -a "${extracted}/etc/nginx/." /etc/nginx/ 2>/dev/null || true
  cp -a "${extracted}/etc/fail2ban/." /etc/fail2ban/ 2>/dev/null || true
  cp -a "${extracted}/etc/ufw/." /etc/ufw/ 2>/dev/null || true

  if [[ -f "${extracted}/etc/sysctl.conf" ]]; then
    cp -a "${extracted}/etc/sysctl.conf" /etc/sysctl.conf
  fi
  if [[ -d "${extracted}/etc/sysctl.d" ]]; then
    cp -a "${extracted}/etc/sysctl.d/." /etc/sysctl.d/
  fi
  if [[ -d "${extracted}/usr/local/etc/xray" ]]; then
    mkdir -p /usr/local/etc/xray
    cp -a "${extracted}/usr/local/etc/xray/." /usr/local/etc/xray/
  fi

  rm -rf "$work"

  echo "正在重载服务..."
  sysctl --system >/dev/null 2>&1 || true
  systemctl reload ssh 2>/dev/null || systemctl restart ssh 2>/dev/null || true
  systemctl reload nginx 2>/dev/null || systemctl restart nginx 2>/dev/null || true
  systemctl restart fail2ban 2>/dev/null || true
  ufw reload 2>/dev/null || true

  echo "回滚完成。请在第二个终端检查服务状态和 SSH 连通性。"
  echo "安装时捕获的运行时状态保存在快照内的 runtime-state.txt。"
}

main() {
  case "${1:-}" in
    --help|-h) usage; exit 0 ;;
    --list) list_snapshots; exit 0 ;;
    "")
      list_snapshots
      echo
      read -r -p "输入要回滚的快照文件名（或按回车取消）: " name
      [[ -z "$name" ]] && { echo "已取消。"; exit 0; }
      if [[ -f "$name" ]]; then
        restore_snapshot "$name"
      elif [[ -f "${BACKUP_DIR}/${name}" ]]; then
        restore_snapshot "${BACKUP_DIR}/${name}"
      else
        echo "未找到: $name"; exit 1
      fi
      ;;
    *)
      if [[ -f "$1" ]]; then
        restore_snapshot "$1"
      elif [[ -f "${BACKUP_DIR}/$1" ]]; then
        restore_snapshot "${BACKUP_DIR}/$1"
      else
        echo "未找到快照: $1"; exit 1
      fi
      ;;
  esac
}

main "$@"
