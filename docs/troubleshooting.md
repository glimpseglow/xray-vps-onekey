# 排障

## 端口检查

直连模式：

```bash
ss -tulnp | grep -E ':443'
```

双模式：

```bash
ss -tulnp | grep -E ':443|:8080|:10443|:20443'
```

## SSH 无法连接

1. 确认端口是否正确（默认 48121）：
   ```bash
   ssh -p 48121 root@<你的服务器IP>
   ```

2. 如果被锁死，通过 VPS 网页控制台（VNC/noVNC）登录后恢复：
   ```bash
   rm /etc/ssh/sshd_config.d/99-xray-vps-onekey.conf
   systemctl restart ssh
   # 或者用回滚脚本
   bash scripts/restore-backup.sh
   ```

## nginx 检查

```bash
nginx -t
systemctl status nginx
journalctl -u nginx -e --no-pager
```

## Xray 检查

```bash
xray run -test -config /usr/local/etc/xray/config.json
systemctl status xray
journalctl -u xray -e --no-pager
```

如果 Xray 报权限错误，检查 xray.service 的 User= 行是否已被注释掉：
```bash
grep -E '^\s*User\s*=' /etc/systemd/system/xray.service
# 应该显示被注释：#User=nobody
```

## Fail2ban 检查

```bash
fail2ban-client status
fail2ban-client status sshd
systemctl status fail2ban
journalctl -u fail2ban -e --no-pager
```

## 证书问题

```bash
/root/.acme.sh/acme.sh --list
ls -la /etc/nginx/ssl/<域名>/
```

强制续签：
```bash
bash install.sh --domain <域名> --cf-key "xxx" --cf-email "xxx" --renew-cert
```

## 查看客户端链接

```bash
bash scripts/print-links.sh
# 或者
cat /etc/xray-vps-onekey/install-summary.private
```

## 回滚到安装前状态

```bash
bash scripts/restore-backup.sh --list
bash scripts/restore-backup.sh /etc/xray-vps-onekey/backups/pre-install-XXXXXXXX-XXXXXX.tar.gz
```
