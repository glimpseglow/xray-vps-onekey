#!/usr/bin/env bash
set -Eeuo pipefail
PROJECT_NAME="xray-vps-onekey"

echo "此操作将移除 ${PROJECT_NAME} 托管的配置，但默认不会删除 nginx/xray/acme.sh 二进制文件。"
read -r -p "确认继续？[y/N] " ans
case "$ans" in
  y|Y|yes|YES) ;;
  *) echo "已取消。"; exit 0 ;;
esac

rm -f /etc/nginx/stream-enabled/xray-vps-onekey.conf
rm -f /etc/nginx/sites-enabled/xray-vps-onekey-ws.conf
rm -f /etc/nginx/sites-available/xray-vps-onekey-ws.conf
rm -f /etc/fail2ban/jail.d/xray-vps-onekey-sshd.local
rm -f /etc/ssh/sshd_config.d/99-xray-vps-onekey.conf
rm -f /etc/sysctl.d/99-xray-vps-onekey.conf

systemctl reload ssh || true
systemctl reload nginx || true
systemctl restart fail2ban || true
sysctl --system >/dev/null || true

echo "托管配置已移除。状态文件保留在 /etc/${PROJECT_NAME}，如需删除 secrets 和备份请手动处理。"
