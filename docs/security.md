# 安全说明

## 不要公开这些文件

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

## root 执行警告

本脚本会修改 SSH、防火墙、nginx、Xray、Fail2ban、sysctl 和证书配置。以 root 执行前请先阅读脚本内容。

## curl bash 风险

不要在不了解脚本内容的情况下直接执行远程脚本。推荐先下载、阅读、校验，再执行。

## SSH 风险

**安装前必须配置好 SSH 密钥登录。** 详见 README.md 的"安装前必读：SSH 密钥准备"章节。

安装后 root 只能通过密钥登录（`PermitRootLogin=prohibit-password`）。`--strict-ssh` 会彻底禁用密码登录，**只有确认密钥登录正常后才能使用**。

如果被锁死，通过 VPS 网页控制台恢复：

```bash
rm /etc/ssh/sshd_config.d/99-xray-vps-onekey.conf
systemctl restart ssh
# 或者用回滚脚本
bash scripts/restore-backup.sh
```

## Cloudflare 凭据安全

推荐使用 API Token（权限最小化）而非 Global API Key。详见 [configuration.md](configuration.md#cloudflare-凭据获取指引)。

安装日志会对 `CF_Key`/`CF_Token`/`REALITY_PRIVATE_KEY`/`XRAY_UUID`/`REALITY_SHORT_ID` 脱敏，但不要公开 `secrets.env`。
