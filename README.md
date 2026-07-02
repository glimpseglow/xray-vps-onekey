# xray-vps-onekey

Debian 12+ / Ubuntu 24.04+ 一行命令部署 **Xray Reality 代理**，支持两种模式：

- **直连模式**（无域名）：Xray Reality 直接监听 `0.0.0.0:443`，无需 nginx、无需域名、无需证书。后续可无缝升级到双模式。
- **双模式**（有域名）：Reality 直连入口 + VLESS WebSocket CDN 入口，nginx stream SNI 分流、acme.sh 证书。

> 适合全新 Debian 12+ / Ubuntu 24.04+ VPS。涉及 root 权限、SSH、防火墙和代理服务配置，执行前请先阅读脚本内容。

## SSH 加固（可选，默认不启用）

**默认不修改 SSH 配置。** 如需启用 SSH 加固（改端口 + 限制 root 登录方式），请先完成以下准备，再用 `--ssh-hardening` 选项。

### 启用 SSH 加固前必须完成

在你的**本地电脑**（不是 VPS）上生成 SSH 密钥并把公钥放到 VPS 的 `/root/.ssh/authorized_keys`：

```bash
# 1. 本地电脑生成密钥（如果已有 ~/.ssh/id_ed25519.pub 可跳过）
ssh-keygen -t ed25519 -C "your_email@example.com"

# 2. 把公钥上传到 VPS（用当前 root 密码登录）
ssh-copy-id root@<你的VPS_IP>

# 3. 验证密钥登录可用（重要！）
ssh root@<你的VPS_IP>
# 能免密登录说明密钥配置成功，才能继续下一步
```

### SSH 加固行为

| 选项 | SSH 端口 | 密码登录 | root 登录 |
| --- | --- | --- | --- |
| `--ssh-hardening` | 改为 48121（或 `--ssh-port` 指定） | **保留** | 仅密钥（`prohibit-password`） |
| `--ssh-hardening --strict-ssh` | 改为 48121 | **禁用** | 仅密钥 |

- **`--ssh-hardening`**：改端口 + root 仅密钥登录，但保留密码登录（防止锁死）。
- **`--ssh-hardening --strict-ssh`**：彻底禁用密码登录。**只有确认密钥登录完全正常后才能用**。

### 安装后的 SSH 连接

```bash
ssh -p 48121 root@<你的VPS_IP>
```

### 如果被锁死

通过 VPS 服务商的网页控制台（VNC/noVNC）登录后执行回滚：

```bash
bash scripts/restore-backup.sh
# 或手动删除本项目的 SSH 配置
rm /etc/ssh/sshd_config.d/99-xray-vps-onekey.conf
systemctl restart ssh
```

## 两种模式架构

### 直连模式（无 --domain）

```text
公网 443
  ↓
Xray Reality (0.0.0.0:443)
```

不安装 nginx，不需要域名和证书。最简部署，后续可无缝升级。

### 双模式（有 --domain）

```text
公网 443
  ↓
nginx stream ssl_preread
  ↓
按 SNI 分流

默认 / 未匹配 SNI
  → 127.0.0.1:10443
  → Xray Reality

CDN 域名，例如 ws2.example.com
  → 127.0.0.1:8080
  → nginx 本地 TLS/WS 反代
  → 127.0.0.1:20443
  → Xray VLESS WebSocket
```

公网默认只开放：

```text
SSH 自定义端口
443/tcp
80/tcp 仅用于启动/证书场景，可按需收紧
```

双模式内部监听：

```text
127.0.0.1:10443  Xray Reality
127.0.0.1:20443  Xray WebSocket
127.0.0.1:8080   nginx WS TLS 反代
```

### 无缝升级

直连模式装好后，随时补域名和 CF 凭据重跑即可升级到双模式：

```bash
bash install.sh --domain ws2.example.com --cf-key "你的CF_Key" --cf-email "你的邮箱"
```

脚本会自动：安装 nginx → 签证书 → Xray Reality 迁移到 127.0.0.1:10443 → 加 WS 入口 → nginx 接管 443 SNI 分流。UUID 和 Reality 密钥保持不变，客户端只需新增 CDN-WS 链接。

## 功能清单

必选核心：

- Xray 官方安装脚本安装
- `/usr/local/etc/xray/config.json` 自动生成
- Reality 直连配置
- VLESS WebSocket CDN 配置（双模式）
- nginx-full + stream `ssl_preread` SNI 分流（双模式）
- acme.sh + Cloudflare DNS 证书（双模式）
- UFW 防火墙
- BBR
- 关闭 IPv6
- SSH 加固（可选，`--ssh-hardening` 启用）
- Fail2ban
- pre-flight 装前检查
- doctor 装后健康检查
- 安装前全量配置快照备份（可 `--skip-backup` 跳过）
- 幂等重跑设计
- 敏感信息权限收紧和日志脱敏

## 安装方式

### 推荐：先下载审查，再执行

```bash
curl -fsSL -o install.sh https://raw.githubusercontent.com/glimpseglow/xray-vps-onekey/main/install.sh
less install.sh
bash install.sh --domain ws2.example.com --cf-key "你的CF_Key" --cf-email "你的邮箱"
```

### 直连模式（无域名，最简部署）

```bash
bash install.sh
```

不需要域名和 Cloudflare 凭据，Xray Reality 直接监听 443。后续可补 `--domain` 升级到双模式。

### 快速方式

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/glimpseglow/xray-vps-onekey/main/install.sh) \
  --domain ws2.example.com \
  --cf-key "你的CF_Key" \
  --cf-email "你的邮箱"
```

### 更推荐的 Cloudflare API Token 方式

```bash
bash install.sh \
  --domain ws2.example.com \
  --cf-token "你的CF_Token" \
  --cf-zone-id "你的CF_Zone_ID" \
  --cf-account-id "你的CF_Account_ID"
```

### 自定义参数

```bash
bash install.sh \
  --domain ws2.example.com \
  --cf-key "你的CF_Key" \
  --cf-email "你的邮箱" \
  --ssh-port 48121 \
  --ws-path /gl2025ws \
  --reality-dest www.microsoft.com
```

Cloudflare 凭据获取步骤见 [docs/configuration.md](docs/configuration.md#cloudflare-凭据获取指引)。

严格 SSH 模式会禁用密码登录。只有确认已经能用 SSH 密钥登录后再使用：

```bash
bash install.sh --domain ws2.example.com --cf-key "xxx" --cf-email "you@example.com" --strict-ssh
```

## 安全安装建议

`curl | bash` 很方便，但它会把远程脚本交给 root 执行。更安全的方式是：

```bash
curl -fsSL -o install.sh https://raw.githubusercontent.com/glimpseglow/xray-vps-onekey/main/install.sh
less install.sh
bash install.sh --help
```

发布 Release 时建议同时提供：

```bash
sha256sum xray-vps-onekey.zip > xray-vps-onekey.zip.sha256
```

用户可以校验：

```bash
sha256sum -c xray-vps-onekey.zip.sha256
```

## 安装后查看链接

```bash
/etc/xray-vps-onekey/install-summary.private
```

或者在项目目录执行：

```bash
bash scripts/print-links.sh
```

会输出两个客户端链接：

- Reality Direct
- CDN WebSocket

## 重要文件

```text
/etc/xray-vps-onekey/state.env              非敏感状态
/etc/xray-vps-onekey/secrets.env            UUID、私钥、Cloudflare 凭据等敏感信息，权限 600
/etc/xray-vps-onekey/install-summary.public 可截图分享的摘要
/etc/xray-vps-onekey/install-summary.private 完整客户端链接，权限 600
/usr/local/etc/xray/config.json             Xray 服务端配置，权限 600
/etc/nginx/stream-enabled/xray-vps-onekey.conf
/etc/nginx/sites-available/xray-vps-onekey-ws.conf
/etc/fail2ban/jail.d/xray-vps-onekey-sshd.local
/etc/ssh/sshd_config.d/99-xray-vps-onekey.conf
/etc/sysctl.d/99-xray-vps-onekey.conf
```

## 健康检查

```bash
bash checks/doctor.sh
```

会检查：

- ssh/nginx/xray/fail2ban 服务状态
- UFW 状态
- 443/8080/10443/20443 监听状态
- BBR 状态
- IPv6 关闭状态
- nginx 配置语法
- Xray 配置语法

## 备份与回滚

安装前会自动对现有配置做一次快照（除非传 `--skip-backup`），保存为：

```text
/etc/xray-vps-onekey/backups/pre-install-YYYYmmdd-HHMMSS.tar.gz
```

包含 nginx、ssh、xray、sysctl、fail2ban、ufw 的配置，以及安装时的运行时状态（监听端口、服务列表、UFW 规则、BBR/IPv6 当前值）。

列出快照：

```bash
bash scripts/restore-backup.sh --list
```

回滚到某个快照（会覆盖当前配置并重载服务，执行前会先列出内容并要求确认）：

```bash
bash scripts/restore-backup.sh /etc/xray-vps-onekey/backups/pre-install-20240101-120000.tar.gz
```

## 卸载托管配置

```bash
bash scripts/uninstall.sh
```

默认只删除本项目托管的配置，不会自动删除 nginx、xray、acme.sh 二进制，也不会删除 `/etc/xray-vps-onekey` 中的 secrets 和备份。

## 注意事项

- 支持 Debian 12+、Ubuntu 24.04+。
- 建议使用全新 VPS。
- SSH 加固默认不启用，需 `--ssh-hardening` 选项。启用前必须配置好 SSH 密钥登录，否则可能锁死。
- `--strict-ssh` 需配合 `--ssh-hardening` 使用，启用前必须确认 SSH 密钥可登录。
- Cloudflare API Token 比 Global API Key 更安全。
- 安装日志会尽量脱敏，但不要公开 `/etc/xray-vps-onekey/secrets.env`。

## License

MIT
