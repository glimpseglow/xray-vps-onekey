# 配置说明

## 模式

| 模式 | 条件 | 入口 |
| --- | --- | --- |
| 直连模式 | 不传 `--domain` | Xray Reality 直接监听 `0.0.0.0:443` |
| 双模式 | 传 `--domain` + CF 凭据 | nginx SNI 分流 443 → Reality + VLESS WS CDN |

直连模式可随时补 `--domain` 无缝升级到双模式，UUID 和 Reality 密钥保持不变。

## 状态目录

```text
/etc/xray-vps-onekey/
├── state.env                 非敏感状态（端口、域名、模式等），权限 600
├── secrets.env               UUID、私钥、Cloudflare 凭据，权限 600
├── install-summary.public    可截图分享的摘要，权限 644
├── install-summary.private   完整客户端链接，权限 600
└── backups/                  安装前快照 + 按文件懒备份
```

## 主要配置文件

```text
/usr/local/etc/xray/config.json                              Xray 服务端配置，权限 600
/etc/nginx/stream-enabled/xray-vps-onekey.conf               nginx stream SNI 分流（双模式）
/etc/nginx/sites-available/xray-vps-onekey-ws.conf           nginx WS 反代（双模式）
/etc/fail2ban/jail.d/xray-vps-onekey-sshd.local              Fail2ban SSH jail
/etc/ssh/sshd_config.d/99-xray-vps-onekey.conf               SSH 加固
/etc/sysctl.d/99-xray-vps-onekey.conf                        BBR + 关闭 IPv6
```

## 端口

### 直连模式

```text
0.0.0.0:443       Xray Reality（公网入口）
SSH 自定义端口    默认 48121
```

### 双模式

```text
公网 443          nginx stream ssl_preread SNI 分流
127.0.0.1:10443   Xray Reality
127.0.0.1:20443   Xray WS
127.0.0.1:8080    nginx WS TLS 反代
SSH 自定义端口    默认 48121
```

## Cloudflare 凭据获取指引

双模式需要 Cloudflare 凭据来通过 DNS-01 验证签发 TLS 证书。有两种方式，**推荐使用 API Token**（权限最小化，比 Global API Key 更安全）。

### 方式 A：API Token（推荐）

需要 4 个参数：`--cf-token`、`--cf-zone-id`、`--cf-account-id`、`--domain`

#### 1. 域名需托管在 Cloudflare

在 Cloudflare 添加你的域名并把 NS 改到 Cloudflare（这步通常在注册商后台把 NS 改为 Cloudflare 分配的两个 NS）。域名的 DNS 记录由 Cloudflare 管理。

#### 2. 获取 Zone ID

1. 登录 https://dash.cloudflare.com/
2. 点击进入你的域名概览页（Overview）
3. 右下角 **API** 区块可以看到 **Zone ID(区域ID)**

#### 3. 获取 Account ID

在同一页面，右下角 **Account ID(帐户)** 就在 Zone ID 上方或下方。也可以从 URL 看到：
```
https://dash.cloudflare.com/<Account_ID>/home
```

#### 4. 创建 API Token

1. 访问 https://dash.cloudflare.com/profile/api-tokens
2. 点击 **Create Token**
3. 选择 **Edit zone DNS** 模板(编辑区域DNS)（推荐），或自定义：
   - **Permissions**：
     - `Zone(区域)` - `DNS` - `Edit(编辑)`
     - `Zone(区域)` - `Zone(区域)` - `Read(读取)`
   - **Zone Resources(区域资源)**：`Include(包含)` - `Specific zone(特定区域)` - 选择你的域名
4. 点击 **Continue to summary(继续以显示摘要)** → **Create Token(创建令牌)**
5. 复制 Token（只显示一次）

#### 5. 使用

```bash
bash install.sh \
  --domain ws2.example.com \
  --cf-token "你的Token" \
  --cf-zone-id "你的Zone_ID" \
  --cf-account-id "你的Account_ID"
```

### 方式 B：Global API Key（简单但权限过大）

需要 3 个参数：`--cf-key`、`--cf-email`、`--domain`

Global API Key 拥有你账户的完整权限，泄露风险大，不推荐。仅在没有 Token 条件下临时使用。

#### 1. 获取 Global API Key

1. 访问 https://dash.cloudflare.com/profile/api-tokens
2. 页面下方 **Global API Key** 区块点击 **View**
3. 输入密码 + 过 CAPTCHA，复制 Key

#### 2. 使用

```bash
bash install.sh \
  --domain ws2.example.com \
  --cf-key "你的Global_API_Key" \
  --cf-email "你的Cloudflare登录邮箱"
```

### 两种方式对比

| | API Token | Global API Key |
| --- | --- | --- |
| 权限范围 | 只能编辑指定域名的 DNS | 整个账户所有操作 |
| 泄露风险 | 小 | 大 |
| 需要参数 | `--cf-token` `--cf-zone-id` `--cf-account-id` | `--cf-key` `--cf-email` |
| 推荐度 | 推荐 | 不推荐，仅临时用 |

### 域名 DNS 要求

acme.sh 通过 DNS-01 验证签发证书，会自动用 CF 凭据在 Cloudflare 创建 `_acme-challenge.<域名>` TXT 记录。确保：

- 域名已托管在 Cloudflare
- DNS 记录由 Cloudflare 管理
- 用于 CDN/WS 的子域名（如 `ws2.example.com`）**建议先关闭 Cloudflare 代理（小灰云）**，让 DNS 直接解析到 VPS IP，等证书签发后再按需开启代理（橙云）

### DNS API 调试

如果证书签发失败，可手动测试 CF 凭据是否有效：

```bash
export CF_Token="你的Token"
export CF_Zone_ID="你的Zone_ID"
export CF_Account_ID="你的Account_ID"
# 或
export CF_Key="你的Global_Key"
export CF_Email="你的邮箱"

/root/.acme.sh/acme.sh --issue --dns dns_cf -d ws2.example.com --keylength ec-256 --debug 2
```

日志里 `CF_Key`/`CF_Token` 会被脚本脱敏为 `[REDACTED]`，但 acme.sh 自己的输出可能不脱敏，调试时注意保护。
