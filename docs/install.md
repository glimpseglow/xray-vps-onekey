# 安装说明

## 推荐环境

- Debian 12
- root 用户
- 512MB+ 内存
- 1GB+ 可用磁盘
- 双模式还需要：已解析到 VPS 的 Cloudflare 域名

## 直连模式（无需域名）

```bash
bash install.sh
```

## 双模式（需要域名）

```bash
bash install.sh \
  --domain ws2.example.com \
  --cf-key "你的CF_Key" \
  --cf-email "你的邮箱" \
  --ws-path /gl2025ws
```

Cloudflare 凭据获取步骤见 [configuration.md](configuration.md#cloudflare-凭据获取指引)。

## 从直连模式无缝升级到双模式

```bash
bash install.sh --domain ws2.example.com --cf-key "你的CF_Key" --cf-email "你的邮箱"
```

UUID 和 Reality 密钥保持不变，客户端只需新增 CDN-WS 链接。

## SSH 加固（可选）

默认不修改 SSH 配置。如需启用：

```bash
# 加固模式（改端口 + root 仅密钥登录，保留密码登录）
bash install.sh --ssh-hardening

# 严格模式（彻底禁用密码登录，需确认密钥登录正常后使用）
bash install.sh --ssh-hardening --strict-ssh
```

启用前必须先配置好 SSH 密钥登录，详见 README.md 的 SSH 加固章节。

## 自定义参数

```bash
bash install.sh \
  --ssh-port 48121 \
  --ws-path /gl2025ws \
  --reality-dest www.microsoft.com
```
