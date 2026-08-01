# 通用 SMTP Relay 一键部署

这个项目用于在一台**可以访问上游 SMTP 的中继服务器**上部署 SMTP Relay。部署完成后，应用服务器上的业务项目只需要连接中继服务器的 `IP:端口`，就可以通过 Gmail、Outlook、Microsoft 365、Amazon SES、SendGrid、Mailgun、Postmark、Resend 等主流 SMTP 服务发信。

```text
应用服务器项目
  ↓ SMTP + STARTTLS + Relay 用户名密码
中继服务器 Postfix SMTP Relay
  ↓ SMTP + STARTTLS 或 SSL/TLS + 上游 SMTP 账号/API Key
Gmail / Outlook / Microsoft 365 / SES / SendGrid / Mailgun / ...
```

## 适用场景

- 应用服务器所在网络无法直接访问 25/465/587 等 SMTP 出站端口；
- 中继服务器可以正常访问上游 SMTP；
- 业务项目只能配置 SMTP，不方便改成 HTTP 邮件 API；
- 需要传输加密，避免明文 SMTP；
- 需要避免开放中继，只有指定应用服务器能用。

## 支持的上游 SMTP 预设

安装脚本内置这些主流服务商：

| 选项 | 服务商 | SMTP 地址 | 端口 | 加密 |
|---:|---|---|---:|---|
| 0 | 自动检测可用服务商（推荐） | - | - | - |
| 1 | Gmail / Google Workspace | `smtp.gmail.com` | 587 | STARTTLS |
| 2 | Outlook / Hotmail 个人邮箱 | `smtp-mail.outlook.com` | 587 | STARTTLS |
| 3 | Microsoft 365 / Office 365 | `smtp.office365.com` | 587 | STARTTLS |
| 4 | Yahoo Mail | `smtp.mail.yahoo.com` | 587 | STARTTLS |
| 5 | Zoho Mail | `smtp.zoho.com` | 587 | STARTTLS |
| 6 | Amazon SES | `email-smtp.<region>.amazonaws.com` | 587 | STARTTLS |
| 7 | SendGrid | `smtp.sendgrid.net` | 587 | STARTTLS |
| 8 | Mailgun | `smtp.mailgun.org` | 587 | STARTTLS |
| 9 | Postmark | `smtp.postmarkapp.com` | 587 | STARTTLS |
| 10 | Resend | `smtp.resend.com` | 587 | STARTTLS |
| 11 | Mailtrap | `live.smtp.mailtrap.io` | 587 | STARTTLS |
| 12 | QQ 邮箱 | `smtp.qq.com` | 465 | SSL/TLS |
| 13 | 163/网易邮箱 | `smtp.163.com` | 465 | SSL/TLS |
| 14 | 自定义 SMTP | 自己填写 | 自己填写 | STARTTLS 或 SSL/TLS |

> 注意：不同服务商会调整策略，实际以服务商后台给出的 SMTP 信息为准。脚本的“自定义 SMTP”可以覆盖任意服务商。

## 重要说明

### Cloudflare 小黄云

普通 Cloudflare 小黄云不适合直接代理 SMTP/TCP 端口。

如果你想使用域名，例如：

```text
smtp-relay.example.com:2525
```

请将这个 DNS 记录设置为：

```text
DNS only / 灰云
```

不要开启普通代理小黄云。除非你使用 Cloudflare Spectrum，或者应用服务器侧也运行 `cloudflared` 做 TCP 转发。

### 两类密码

部署时会让你输入两类密码：

1. **上游 SMTP 密码 / 授权码 / API Key**

   中继服务器需要用它登录上游 SMTP。这个凭据会保存在中继服务器：

   ```text
   /etc/postfix/sasl_passwd
   /etc/postfix/sasl_passwd.db
   ```

   脚本会设置为 root-only 权限。

2. **Relay 密码**

   应用服务器上的项目连接中继服务器时使用。

   业务项目里填写的是这个密码，不是上游 SMTP 密码。

建议不要使用主账号真实密码，优先使用：

- App Password / 客户端授权码；
- 专门用于发信的邮箱账号；
- SES/SendGrid/Mailgun/Postmark/Resend 等服务商的 SMTP 专用凭据或 API Key；
- 最小权限账号。

## 系统要求

中继服务器需要是：

- Ubuntu 20.04+ / Debian 11+；
- root 权限；
- 能访问你选择的上游 SMTP 地址和端口；
- 云厂商安全组允许应用服务器访问你设置的中继服务端口，例如 `2525`。

## 快速部署

在中继服务器上执行：

```bash
git clone https://github.com/aichenshidelibing/smtp-relay-gateway.git
cd smtp-relay-gateway
sudo bash scripts/install-smtp-relay.sh
```

如果你是直接上传这个文件夹，也可以：

```bash
cd smtp-relay-gateway
sudo bash scripts/install-smtp-relay.sh
```

脚本会交互式询问：

- 中继服务对应用服务器开放的端口，默认 `2525`；
- 允许访问中继服务的应用服务器公网 IP/CIDR；
- 上游 SMTP 服务商；
- 上游 SMTP 用户名；
- 上游 SMTP 密码、授权码、App Password 或 API Key；
- 应用服务器连接中继服务用的密码；
- TLS 证书方式。

脚本会自动处理这些值，不再要求手动填写：

- Relay 用户名密码可以在安装时自定义添加多个；
- `mailname` / hostname 自动选择；
- Let's Encrypt 申请不要求填写邮箱；
- 基础限流参数使用安全默认值。

安装时脚本会：
- 自动检测可用的服务商（推荐选项 0）；
- 验证上游 SMTP 账号凭据是否有效；
- 支持添加多个 Relay 用户。

## 各服务商凭据获取教程

> 说明：各服务商后台界面会调整，下面步骤按常见路径整理。若页面名称略有不同，以服务商当前后台为准。所有密码、授权码、API Key 都只在部署脚本中输入一次，脚本会写入中继服务器的 `/etc/postfix/sasl_passwd`，不要提交到代码仓库。

### Gmail / Google Workspace

适合个人 Gmail、Google Workspace 企业邮箱。

SMTP 配置：

```text
SMTP Host: smtp.gmail.com
SMTP Port: 587
Encryption: STARTTLS
Username: 完整 Gmail / Workspace 邮箱地址
Password: App Password
```

获取 App Password：

1. 登录 Google 账号。
2. 打开 Google Account：<https://myaccount.google.com/>
3. 进入 **Security / 安全性**。
4. 开启 **2-Step Verification / 两步验证**。
5. 开启后，在安全性页面搜索或进入 **App passwords / 应用专用密码**。
6. 创建一个新的 App Password，名称可以写：

   ```text
   smtp-relay-gateway
   ```

7. 复制生成的 16 位应用专用密码。
8. 运行本项目安装脚本时：
   - 服务商选择 `Gmail / Google Workspace`；
   - 用户名填写完整邮箱；
   - 密码填写刚生成的 App Password。

注意事项：

- 不要填写网页登录密码，优先使用 App Password。
- 如果是 Google Workspace，管理员可能禁用了 App Password 或 SMTP 相关能力，需要管理员在 Workspace Admin Console 放行。
- `From` 建议使用登录邮箱，或使用 Google Workspace 已授权的别名。
- Gmail 有每日发送额度，个人 Gmail 不适合大量业务邮件。

### Outlook / Hotmail 个人邮箱

适合 `@outlook.com`、`@hotmail.com`、`@live.com` 等个人邮箱。

SMTP 配置：

```text
SMTP Host: smtp-mail.outlook.com
SMTP Port: 587
Encryption: STARTTLS
Username: 完整 Outlook/Hotmail 邮箱地址
Password: 账号密码或 App Password
```

获取凭据：

1. 登录 Microsoft Account：<https://account.microsoft.com/>
2. 进入 **Security / 安全性**。
3. 如果账号开启了双重验证，进入高级安全选项，创建 **App password / 应用密码**。
4. 运行安装脚本时：
   - 服务商选择 `Outlook / Hotmail 个人邮箱`；
   - 用户名填写完整邮箱；
   - 密码填写 App Password 或账号密码。

注意事项：

- 如果开启了 MFA，通常需要 App Password。
- 部分个人 Outlook 账号可能限制 SMTP AUTH 或触发安全风控。
- `From` 建议使用登录邮箱，不要伪造成其他域名。

### Microsoft 365 / Office 365

适合企业 Microsoft 365 邮箱。

SMTP 配置：

```text
SMTP Host: smtp.office365.com
SMTP Port: 587
Encryption: STARTTLS
Username: 完整 Microsoft 365 邮箱地址
Password: 邮箱密码或 App Password
```

获取和启用 SMTP AUTH：

1. 确认你有 Microsoft 365 管理员权限，或者让管理员操作。
2. 登录 Microsoft 365 Admin Center：<https://admin.microsoft.com/>
3. 找到对应用户邮箱。
4. 检查该邮箱是否允许 **Authenticated SMTP / SMTP AUTH**。
5. 如果租户或邮箱禁用了 SMTP AUTH，需要启用后再使用。
6. 如果账号开启 MFA，需要使用 App Password，或者改用支持的认证方式/专用发信账号。
7. 运行安装脚本时：
   - 服务商选择 `Microsoft 365 / Office 365`；
   - 用户名填写完整邮箱；
   - 密码填写邮箱密码或 App Password。

常见 PowerShell 检查思路：

```powershell
Get-CASMailbox user@example.com | Select SmtpClientAuthenticationDisabled
```

启用单个邮箱 SMTP AUTH 的常见思路：

```powershell
Set-CASMailbox user@example.com -SmtpClientAuthenticationDisabled $false
```

注意事项：

- 租户级别也可能禁用 SMTP AUTH。
- `From` 必须是登录邮箱，或者该邮箱拥有对应地址的 Send As / Send on behalf 权限。
- 若遇到 `SmtpClientAuthentication is disabled`，优先检查 SMTP AUTH。
- 若遇到 `SendAsDenied`，检查发件地址权限。

### Yahoo Mail

SMTP 配置：

```text
SMTP Host: smtp.mail.yahoo.com
SMTP Port: 587
Encryption: STARTTLS
Username: 完整 Yahoo 邮箱地址
Password: App Password
```

获取 App Password：

1. 登录 Yahoo Account Security 页面。
2. 开启两步验证。
3. 找到 **Generate app password / 生成应用密码**。
4. 创建应用密码，名称可以写：

   ```text
   smtp-relay-gateway
   ```

5. 运行安装脚本时：
   - 服务商选择 `Yahoo Mail`；
   - 用户名填写完整 Yahoo 邮箱；
   - 密码填写 App Password。

注意事项：

- Yahoo 通常要求 App Password，不建议使用网页登录密码。
- `From` 建议使用登录邮箱。

### Zoho Mail

SMTP 配置：

```text
SMTP Host: smtp.zoho.com
SMTP Port: 587
Encryption: STARTTLS
Username: 完整 Zoho 邮箱地址
Password: 账号密码或 App Password
```

获取凭据：

1. 登录 Zoho Mail / Zoho Accounts。
2. 如果账号开启 MFA，进入安全设置创建 **App Password**。
3. 如果是组织邮箱，确认管理员允许 SMTP/IMAP 访问。
4. 运行安装脚本时：
   - 服务商选择 `Zoho Mail`；
   - 用户名填写完整 Zoho 邮箱；
   - 密码填写 App Password 或账号密码。

注意事项：

- Zoho 有不同区域节点，部分账号可能需要使用区域 SMTP，例如 `.eu`、`.in` 等。若默认 `smtp.zoho.com` 不适用，使用安装脚本的 `自定义 SMTP`。
- `From` 使用 Zoho 已验证或允许的发件地址。

### Amazon SES

适合生产业务发信，推荐用于较大规模邮件。

SMTP 配置：

```text
SMTP Host: email-smtp.<region>.amazonaws.com
SMTP Port: 587
Encryption: STARTTLS
Username: SES SMTP Username
Password: SES SMTP Password
```

获取 SES SMTP Credentials：

1. 登录 AWS Console。
2. 进入 **Amazon SES**。
3. 选择你要发信的 Region，例如：

   ```text
   us-east-1
   ap-southeast-1
   eu-west-1
   ```

4. 在 SES 中验证发件身份：
   - 验证域名；或
   - 验证单个邮箱。
5. 配置域名 DNS：SPF/DKIM/DMARC，尤其是 DKIM。
6. 进入 SES 的 **SMTP settings / SMTP 设置**。
7. 点击 **Create SMTP credentials / 创建 SMTP 凭据**。
8. 保存生成的：
   - SMTP Username；
   - SMTP Password。
9. 运行安装脚本时：
   - 服务商选择 `Amazon SES`；
   - 输入 SES Region；
   - 用户名填写 SES SMTP Username；
   - 密码填写 SES SMTP Password。

注意事项：

- SES SMTP 凭据不是 AWS Access Key，也不是 IAM Secret Access Key。
- SES sandbox 状态下，只能发给已验证的收件地址。
- 生产使用前需要申请移出 sandbox。
- `From` 必须是 SES 已验证的域名或邮箱。

### SendGrid

SMTP 配置：

```text
SMTP Host: smtp.sendgrid.net
SMTP Port: 587
Encryption: STARTTLS
Username: apikey
Password: SendGrid API Key
```

获取 API Key：

1. 登录 SendGrid 控制台。
2. 进入 **Settings** → **API Keys**。
3. 点击 **Create API Key**。
4. 权限建议选择最小可用权限。通常只发信可选择 Mail Send 权限。
5. 创建后复制 API Key。
6. 运行安装脚本时：
   - 服务商选择 `SendGrid`；
   - 用户名填写固定值：

     ```text
     apikey
     ```

   - 密码填写 SendGrid API Key。

注意事项：

- SendGrid 的 SMTP 用户名通常不是你的邮箱，而是固定 `apikey`。
- 需要先完成 Sender Authentication / Domain Authentication。
- `From` 必须是已验证 sender 或已认证域名下的地址。

### Mailgun

SMTP 配置：

```text
SMTP Host: smtp.mailgun.org
SMTP Port: 587
Encryption: STARTTLS
Username: Mailgun SMTP Login
Password: Mailgun SMTP Password
```

获取 SMTP 凭据：

1. 登录 Mailgun 控制台。
2. 添加并验证发信域名，例如：

   ```text
   mg.example.com
   ```

3. 按 Mailgun 提示配置 DNS，包括 SPF、DKIM、CNAME/MX 等。
4. 进入对应 Domain 的 **SMTP credentials / SMTP 凭据** 页面。
5. 获取或创建 SMTP 用户，常见格式：

   ```text
   postmaster@mg.example.com
   ```

6. 设置或复制 SMTP Password。
7. 运行安装脚本时：
   - 服务商选择 `Mailgun`；
   - 用户名填写 SMTP Login；
   - 密码填写 SMTP Password。

注意事项：

- EU 区域账号可能需要不同 SMTP Host。若默认 `smtp.mailgun.org` 不适用，使用 `自定义 SMTP`。
- `From` 使用 Mailgun 已验证域名下的地址。

### Postmark

SMTP 配置：

```text
SMTP Host: smtp.postmarkapp.com
SMTP Port: 587
Encryption: STARTTLS
Username: Server API Token
Password: Server API Token
```

获取 Server API Token：

1. 登录 Postmark。
2. 创建或进入一个 Server。
3. 进入 Server 的 **API Tokens** 或 **Credentials** 页面。
4. 复制 **Server API Token**。
5. 确认 Sender Signature 或 Domain 已验证。
6. 运行安装脚本时：
   - 服务商选择 `Postmark`；
   - 用户名填写 Server API Token；
   - 密码也填写 Server API Token。

注意事项：

- Postmark SMTP 的用户名和密码通常都填 Server API Token。
- `From` 必须是已验证 Sender Signature 或已认证域名地址。

### Resend

SMTP 配置：

```text
SMTP Host: smtp.resend.com
SMTP Port: 587
Encryption: STARTTLS
Username: resend
Password: Resend API Key
```

获取 API Key：

1. 登录 Resend 控制台。
2. 添加并验证发信域名。
3. 按 Resend 提示配置 DNS，包括 SPF/DKIM。
4. 进入 **API Keys**。
5. 创建新的 API Key。
6. 运行安装脚本时：
   - 服务商选择 `Resend`；
   - 用户名通常填写：

     ```text
     resend
     ```

   - 密码填写 Resend API Key。

注意事项：

- `From` 必须使用 Resend 已验证域名下的地址。
- 如果 Resend 后台给出不同用户名，以后台显示为准。

### Mailtrap

适合开发测试，也可以使用 Mailtrap Email Sending 做正式发信。

SMTP 配置：

```text
SMTP Host: live.smtp.mailtrap.io
SMTP Port: 587
Encryption: STARTTLS
Username: Mailtrap SMTP Username
Password: Mailtrap SMTP Password / Token
```

获取 SMTP 凭据：

1. 登录 Mailtrap。
2. 如果是测试收件箱，进入对应 Inbox 的 SMTP Settings。
3. 如果是正式 Email Sending，进入 Sending Domains 并验证域名。
4. 在 Mailtrap 提供的 SMTP 配置中复制：
   - Host；
   - Port；
   - Username；
   - Password。
5. 运行安装脚本时：
   - 服务商选择 `Mailtrap`；
   - 用户名填写 Mailtrap 提供的 SMTP Username；
   - 密码填写 Mailtrap 提供的 SMTP Password / Token。

注意事项：

- 测试 Inbox 的邮件不会真正投递到收件人邮箱，适合开发测试。
- 正式发信需要使用 Email Sending 并完成域名验证。
- 如果 Mailtrap 后台给的 Host 不是 `live.smtp.mailtrap.io`，使用 `自定义 SMTP`。

### QQ 邮箱

SMTP 配置：

```text
SMTP Host: smtp.qq.com
SMTP Port: 465
Encryption: SSL/TLS
Username: 完整 QQ 邮箱地址
Password: SMTP 授权码
```

获取授权码：

1. 登录 QQ 邮箱网页版。
2. 进入 **设置**。
3. 找到 **账户** 或 **POP3/IMAP/SMTP/Exchange/CardDAV/CalDAV 服务**。
4. 开启 SMTP 相关服务，通常是：
   - POP3/SMTP；或
   - IMAP/SMTP。
5. 按页面提示完成短信/安全验证。
6. 生成并复制 **授权码**。
7. 运行安装脚本时：
   - 服务商选择 `QQ 邮箱`；
   - 用户名填写完整 QQ 邮箱；
   - 密码填写授权码，不是 QQ 登录密码。

注意事项：

- QQ 邮箱通常使用授权码，不使用 QQ 密码。
- 本项目预设使用 `465 SSL/TLS`，脚本会自动配置 `smtp_tls_wrappermode = yes`。

### 163 / 网易邮箱

SMTP 配置：

```text
SMTP Host: smtp.163.com
SMTP Port: 465
Encryption: SSL/TLS
Username: 完整 163 邮箱地址
Password: 客户端授权码
```

获取客户端授权码：

1. 登录 163 / 网易邮箱网页版。
2. 进入 **设置**。
3. 找到 **POP3/SMTP/IMAP** 或 **客户端授权密码**。
4. 开启 SMTP/IMAP/POP3 相关服务。
5. 按页面提示完成手机验证。
6. 创建并复制 **客户端授权码**。
7. 运行安装脚本时：
   - 服务商选择 `163/网易邮箱`；
   - 用户名填写完整 163 邮箱；
   - 密码填写客户端授权码，不是网页登录密码。

注意事项：

- 网易邮箱通常要求客户端授权码。
- 本项目预设使用 `465 SSL/TLS`。
- 如果你使用的是企业网易邮箱或其他网易域名邮箱，SMTP Host 可能不同，请用 `自定义 SMTP`。

### 自定义 SMTP

如果你的服务商不在预设里，或者服务商后台给出了不同 SMTP 地址，选择 `自定义 SMTP`。

你需要准备：

```text
SMTP Host
SMTP Port
加密方式：STARTTLS 或 SSL/TLS wrapper
SMTP Username
SMTP Password / Token / API Key
允许使用的 From 地址
```

选择建议：

- 端口 `587` 通常选择 `STARTTLS`；
- 端口 `465` 通常选择 `SSL/TLS wrapper`；
- 端口 `25` 不建议用于客户端提交，且很多云服务器会阻断；
- 如果服务商要求固定发件人，业务项目中的 `From` 必须按服务商要求填写。

## TLS 证书

脚本支持四种客户端到中继服务的 TLS 证书方式：

1. **自动生成自签证书**

   最简单，不需要域名。缺点是部分客户端严格校验证书时会报错，需要客户端允许自签证书，或改用正式证书。

2. **自动申请 Let's Encrypt 正式证书**

   中文提示会说明前置条件：

   - 中继服务域名必须已经解析到这台中继服务器；
   - 云厂商安全组和系统防火墙需要临时放行 TCP `80`；
   - 普通 Cloudflare 小黄云要关闭，使用 DNS only / 灰云；
   - 脚本会使用 `certbot standalone` 自动申请；
   - 脚本不会要求填写邮箱，会使用 certbot 的无邮箱注册参数。

3. **使用已有 Let's Encrypt 证书**

   只需要填域名，不需要填完整路径。脚本会自动选择：

   ```text
   /etc/letsencrypt/live/<域名>/fullchain.pem
   /etc/letsencrypt/live/<域名>/privkey.pem
   ```

4. **使用自定义证书目录**

   这是给你已有证书但不是 Let's Encrypt 路径的场景。只需要填目录，不需要分别填证书和私钥路径。目录内必须有：

   ```text
   fullchain.pem
   privkey.pem
   ```

无论选择哪种方式，脚本都会验证：

- 证书文件存在；
- 私钥文件存在；
- 证书能被 OpenSSL 读取；
- 私钥能被 OpenSSL 读取；
- 证书和私钥是否匹配。

验证失败会提示重试，不会直接写入错误证书路径。

## 应用服务器项目配置

部署完成后，应用服务器上的项目填写：

```env
SMTP_HOST=中继服务器IP或灰云域名
SMTP_PORT=2525
SMTP_USER=relay
SMTP_PASS=你部署时设置的中继服务密码
SMTP_SECURE=false
SMTP_STARTTLS=true
```

注意：

- `SMTP_SECURE=false` 通常表示不是 465 隐式 TLS；
- `SMTP_STARTTLS=true` 表示连接后升级到 TLS；
- 本项目默认强制 STARTTLS，未加密连接不会允许认证。

### Node.js / Nodemailer 示例

```js
import nodemailer from "nodemailer";

const transporter = nodemailer.createTransport({
  host: "中继服务器IP或灰云域名",
  port: 2525,
  secure: false,
  requireTLS: true,
  auth: {
    user: "relay",
    pass: "你部署时设置的中继服务密码",
  },
  // 如果你使用自签证书且客户端严格校验，可能需要临时设置：
  // tls: { rejectUnauthorized: false },
});

await transporter.sendMail({
  from: "你的上游SMTP允许的发件地址@example.com",
  to: "recipient@example.com",
  subject: "SMTP Relay 测试",
  text: "这是一封通过 SMTP 中继服务器发出的测试邮件。",
});
```

### Laravel 示例

```env
MAIL_MAILER=smtp
MAIL_HOST=中继服务器IP或灰云域名
MAIL_PORT=2525
MAIL_USERNAME=relay
MAIL_PASSWORD=你部署时设置的中继服务密码
MAIL_ENCRYPTION=tls
MAIL_FROM_ADDRESS=你的上游SMTP允许的发件地址@example.com
MAIL_FROM_NAME="App"
```

### Python 示例

见 [`examples/python-send-test.py`](examples/python-send-test.py)。

## 测试

中继服务器安装脚本会安装 `swaks`。你可以在应用服务器或任意允许来源机器上测试：

```bash
swaks --to recipient@example.com \
  --from 你的上游SMTP允许的发件地址@example.com \
  --server 中继服务器IP或灰云域名 \
  --port 2525 \
  --auth LOGIN \
  --auth-user relay \
  --auth-password '你部署时设置的中继服务密码' \
  --tls
```

如果你使用自签证书，部分客户端可能报证书校验问题。这时可以：

- 换正式证书；
- 或在客户端允许自签证书。

## 防火墙与安全组

脚本会尝试在检测到 `ufw` 时添加规则，但不会自动启用 `ufw`，避免把 SSH 锁掉。

你还需要在云厂商安全组中放行：

```text
来源：应用服务器公网 IP
协议：TCP
端口：2525 或你部署时填写的端口
```

不要对全网开放这个端口。

如果手动使用 ufw：

```bash
sudo ufw allow from <应用服务器IP> to any port 2525 proto tcp
```

启用 ufw 前务必确认 SSH 端口已放行：

```bash
sudo ufw allow 22/tcp
sudo ufw enable
```

## 日志和排错

查看 Postfix 状态：

```bash
systemctl status postfix --no-pager
```

查看日志：

```bash
journalctl -u postfix -f
```

Ubuntu/Debian 也可能有：

```bash
tail -f /var/log/mail.log
```

查看当前关键配置：

```bash
postconf -n
```

查看队列：

```bash
mailq
```

强制刷新队列：

```bash
postqueue -f
```

## 常见问题

### 1. Microsoft 365 报 SMTP AUTH disabled

Microsoft 365 可能默认禁用 SMTP AUTH。需要在管理中心或 PowerShell 为具体邮箱启用 SMTP AUTH。

常见报错类似：

```text
535 5.7.139 Authentication unsuccessful, SmtpClientAuthentication is disabled for the Tenant
```

### 2. SendAsDenied / 发件人不允许

Microsoft 365 通常要求 `From` 与 SMTP 登录账号一致，或者登录账号具有 Send As 权限。

建议业务项目中的 `MAIL_FROM_ADDRESS` 使用上游 SMTP 服务商允许的发件地址。

### 3. 连接超时

检查：

- 云厂商安全组是否放行中继服务端口；
- 中继服务器系统防火墙是否放行；
- 安装时填写的应用服务器 IP 是否正确；
- 应用服务器是否真的从该公网 IP 出口访问；
- Postfix 是否正在监听端口：

```bash
ss -lntp | grep 2525
```

### 4. 认证失败

检查你在业务项目里填写的是 **Relay 用户名/密码**，不是上游 SMTP 密码/API Key。

### 5. 证书校验失败

如果选择自签证书，严格校验证书的客户端会报错。生产建议使用正式证书。

### 6. 上游 SMTP 登录失败

常见原因：

- Gmail/Yahoo/QQ/163 没有使用 App Password/授权码；
- Microsoft 365 没启用 SMTP AUTH；
- SES 使用了 AWS Access Key，而不是 SES SMTP Credentials；
- SendGrid/Postmark/Resend 的用户名填写方式不符合服务商要求；
- `From` 地址不是服务商允许的发件人。

### 7. 邮件进入垃圾箱

注意：

- `From` 不要伪造成未授权域名；
- 使用服务商已验证或允许的发件地址；
- 不要大量群发；
- 不要发送垃圾内容；
- 使用自有域名时配置 SPF、DKIM、DMARC。

## 卸载/回滚

### 推荐：使用卸载脚本

```bash
sudo bash scripts/uninstall-smtp-relay.sh
```

### 手动回滚

脚本每次运行会备份：

```text
/etc/postfix/main.cf.bak.<时间戳>
/etc/postfix/master.cf.bak.<时间戳>
```

如果需要手动回滚，找到对应备份后恢复：

```bash
sudo cp /etc/postfix/main.cf.bak.<时间戳> /etc/postfix/main.cf
sudo cp /etc/postfix/master.cf.bak.<时间戳> /etc/postfix/master.cf
sudo systemctl restart postfix
```

### 单独管理 Relay 用户

```bash
# 添加用户
sudo saslpasswd2 -a postfix -u <mailname> <username>

# 删除用户
sudo saslpasswd2 -d <username>

# 列出所有用户
sudo sasldblistusers2
```

## 文件结构

```text
smtp-relay-gateway/
  README.md
  scripts/
    install-smtp-relay.sh    # 安装脚本
    uninstall-smtp-relay.sh  # 卸载脚本
  examples/
    env.example
    nodemailer-example.js
    python-send-test.py
```

## 卸载

使用项目提供的卸载脚本：

```bash
sudo bash scripts/uninstall-smtp-relay.sh
```

卸载脚本会：
- 停止 Postfix 服务；
- 恢复或清理 Postfix 配置；
- 删除所有 SASL 认证用户；
- 删除上游 SMTP 密码文件；
- 清理 UFW 防火墙规则。

## 生产建议

- 使用灰云域名 + 正式证书；
- 只允许应用服务器 IP 访问中继服务端口；
- 使用专门的发信账号或 SMTP 专用凭据；
- 邮箱类服务尽量开启 MFA，并使用 App Password/授权码；
- 设置业务侧限流；
- 定期查看 `/var/log/mail.log`；
- 邮件量较大时优先使用 Amazon SES、Mailgun、SendGrid、Postmark、Resend 或服务商官方 API。
