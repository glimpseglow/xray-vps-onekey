# 安全策略

## root 执行警告

本脚本会修改 SSH、防火墙、nginx、Xray、Fail2ban、sysctl 和证书配置。以 root 执行前请先阅读脚本内容。

## 敏感文件

以下文件可能包含密钥，不得公开分享：

```text
/etc/xray-vps-onekey/secrets.env
/etc/xray-vps-onekey/install-summary.private
/usr/local/etc/xray/config.json
/etc/nginx/ssl/*/private.key
```

预期权限：

```text
/etc/xray-vps-onekey: 700
secrets.env: 600
install-summary.private: 600
/usr/local/etc/xray/config.json: 600
证书私钥: 600
```

## 推荐安装流程

优先：

```bash
curl -fsSL -o install.sh URL
less install.sh
bash install.sh --help
```

不要在生产服务器上盲目执行 `curl | bash`。

## SSH 安全

**运行安装器之前，必须为 root 配置好 SSH 密钥登录。**

安装器会修改 SSH 端口（默认 48121）并设置 `PermitRootLogin prohibit-password`，即安装后 root 只能通过 SSH 密钥登录。如果你当前用密码登录 root 且没有配置密钥，安装完成后将被锁死。

安装前检查清单：

1. 在本地电脑生成 SSH 密钥（`ssh-keygen -t ed25519`）
2. 将公钥上传到 VPS（`ssh-copy-id root@<VPS_IP>`）
3. 验证密钥登录可用（`ssh root@<VPS_IP>` 应该不再要求密码）

确认以上步骤后再运行安装器。

默认模式（未传 `--strict-ssh`）保留非 root 用户的密码登录，但 root 仍为仅密钥。确认密钥登录在新端口正常后，可用 `--strict-ssh` 彻底禁用密码登录。

如果被锁死，通过 VPS 服务商的网页控制台（VNC/noVNC）恢复：

```bash
rm /etc/ssh/sshd_config.d/99-xray-vps-onekey.conf
systemctl restart ssh
# 或者用回滚脚本
bash scripts/restore-backup.sh
```
