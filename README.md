# 通用 SMTP Relay 一键部署

这个项目用于在一台**可以访问上游 SMTP 的弱服务器**上部署 SMTP Relay。部署完成后，强服务器上的业务项目只需要连接弱服务器的 `IP:端口`，就可以通过 Gmail、Outlook、Microsoft 365、Amazon SES、SendGrid、Mailgun、Postmark、Resend 等主流 SMTP 服务发信。

```text
强服务器项目
  ↓ SMTP + STARTTLS + Relay 用户名密码
弱服务器 Postfix SMTP Relay
  ↓ SMTP + STARTTLS 或 SSL/TLS + 上游 SMTP 账号/API Key
Gmail / Outlook / Microsoft 365 / SES / SendGrid / Mailgun / ...
```

## 适用场景

- 强服务器性能更好，但 25/465/587 等 SMTP 出站被阻断；
- 弱服务器可以正常访问上游 SMTP；
- 业务项目只能配置 SMTP，不方便改成 HTTP 邮件 API；
- 需要传输加密，避免明文 SMTP；
- 需要避免开放中继，只有指定强服务器能用。

## 支持的上游 SMTP 预设

安装脚本内置这些主流服务商：

| 选项 | 服务商 | SMTP 地址 | 端口 | 加密 |
|---:|---|---|---:|---|
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

不要开启普通代理小黄云。除非你使用 Cloudflare Spectrum，或者强服务器侧也运行 `cloudflared` 做 TCP 转发。

### 两类密码

部署时会让你输入两类密码：

1. **上游 SMTP 密码 / 授权码 / API Key**

   弱服务器需要用它登录上游 SMTP。这个凭据会保存在弱服务器：

   ```text
   /etc/postfix/sasl_passwd
   /etc/postfix/sasl_passwd.db
   ```

   脚本会设置为 root-only 权限。

2. **Relay 密码**

   强服务器上的项目连接弱服务器 Relay 时使用。

   业务项目里填写的是这个密码，不是上游 SMTP 密码。

建议不要使用主账号真实密码，优先使用：

- App Password / 客户端授权码；
- 专门用于发信的邮箱账号；
- SES/SendGrid/Mailgun/Postmark/Resend 等服务商的 SMTP 专用凭据或 API Key；
- 最小权限账号。

## 系统要求

弱服务器需要是：

- Ubuntu 20.04+ / Debian 11+；
- root 权限；
- 能访问你选择的上游 SMTP 地址和端口；
- 云厂商安全组允许强服务器访问你设置的 Relay 端口，例如 `2525`。

## 快速部署

在弱服务器上执行：

```bash
git clone <你的仓库地址> smtp-relay-gateway
cd smtp-relay-gateway
sudo bash scripts/install-smtp-relay.sh
```

如果你是直接上传这个文件夹，也可以：

```bash
cd smtp-relay-gateway
sudo bash scripts/install-smtp-relay.sh
```

脚本会交互式询问：

- Relay 对强服务器监听的端口，默认 `2525`；
- 允许访问 Relay 的强服务器公网 IP/CIDR；
- 上游 SMTP 服务商；
- 上游 SMTP 用户名；
- 上游 SMTP 密码、授权码、App Password 或 API Key；
- 强服务器连接 Relay 用的密码；
- TLS 证书方式。

脚本会自动处理这些值，不再要求手动填写：

- Relay 用户名固定为 `relay`；
- `mailname` / hostname 自动选择；
- Let's Encrypt 申请不要求填写邮箱；
- 基础限流参数使用安全默认值。

## 各服务商凭据提示

### Gmail / Google Workspace

- SMTP：`smtp.gmail.com:587`；
- 建议开启两步验证后创建 App Password；
- Google Workspace 可能需要管理员允许 SMTP/应用密码相关策略。

### Outlook / Hotmail

- SMTP：`smtp-mail.outlook.com:587`；
- 使用账号密码或 App Password；
- 如果启用 MFA，通常需要 App Password。

### Microsoft 365 / Office 365

- SMTP：`smtp.office365.com:587`；
- 经常需要为具体邮箱启用 SMTP AUTH；
- `From` 通常要与登录邮箱一致，或者账号具备 Send As 权限。

### Amazon SES

- SMTP：`email-smtp.<region>.amazonaws.com:587`；
- 用户名/密码不是 AWS Access Key，而是 SES 后台生成的 SMTP Credentials；
- SES sandbox 状态下只能发给验证过的地址。

### SendGrid

- SMTP：`smtp.sendgrid.net:587`；
- 用户名通常填 `apikey`；
- 密码填 SendGrid API Key。

### Mailgun

- SMTP：`smtp.mailgun.org:587`；
- 用户名通常类似 `postmaster@mg.example.com`；
- 密码使用 Mailgun SMTP Password。

### Postmark

- SMTP：`smtp.postmarkapp.com:587`；
- 用户名和密码通常都填 Server API Token。

### Resend

- SMTP：`smtp.resend.com:587`；
- 用户名通常填 `resend`；
- 密码填 Resend API Key。

### QQ / 163 邮箱

- 常用 `465 SSL/TLS`；
- 密码请使用邮箱后台生成的客户端授权码，不是网页登录密码。

## TLS 证书

脚本支持四种客户端到 Relay 的 TLS 证书方式：

1. **自动生成自签证书**

   最简单，不需要域名。缺点是部分客户端严格校验证书时会报错，需要客户端允许自签证书，或改用正式证书。

2. **自动申请 Let's Encrypt 正式证书**

   中文提示会说明前置条件：

   - Relay 域名必须已经解析到这台弱服务器；
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

## 强服务器项目配置

部署完成后，强服务器上的项目填写：

```env
SMTP_HOST=弱服务器IP或灰云域名
SMTP_PORT=2525
SMTP_USER=relay
SMTP_PASS=你部署时设置的Relay密码
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
  host: "弱服务器IP或灰云域名",
  port: 2525,
  secure: false,
  requireTLS: true,
  auth: {
    user: "relay",
    pass: "你部署时设置的Relay密码",
  },
  // 如果你使用自签证书且客户端严格校验，可能需要临时设置：
  // tls: { rejectUnauthorized: false },
});

await transporter.sendMail({
  from: "你的上游SMTP允许的发件地址@example.com",
  to: "recipient@example.com",
  subject: "SMTP Relay 测试",
  text: "这是一封通过弱服务器 SMTP Relay 发出的测试邮件。",
});
```

### Laravel 示例

```env
MAIL_MAILER=smtp
MAIL_HOST=弱服务器IP或灰云域名
MAIL_PORT=2525
MAIL_USERNAME=relay
MAIL_PASSWORD=你部署时设置的Relay密码
MAIL_ENCRYPTION=tls
MAIL_FROM_ADDRESS=你的上游SMTP允许的发件地址@example.com
MAIL_FROM_NAME="App"
```

### Python 示例

见 [`examples/python-send-test.py`](examples/python-send-test.py)。

## 测试

弱服务器安装脚本会安装 `swaks`。你可以在强服务器或任意允许来源机器上测试：

```bash
swaks --to recipient@example.com \
  --from 你的上游SMTP允许的发件地址@example.com \
  --server 弱服务器IP或灰云域名 \
  --port 2525 \
  --auth LOGIN \
  --auth-user relay \
  --auth-password '你部署时设置的Relay密码' \
  --tls
```

如果你使用自签证书，部分客户端可能报证书校验问题。这时可以：

- 换正式证书；
- 或在客户端允许自签证书。

## 防火墙与安全组

脚本会尝试在检测到 `ufw` 时添加规则，但不会自动启用 `ufw`，避免把 SSH 锁掉。

你还需要在云厂商安全组中放行：

```text
来源：强服务器公网 IP
协议：TCP
端口：2525 或你部署时填写的端口
```

不要对全网开放这个端口。

如果手动使用 ufw：

```bash
sudo ufw allow from <强服务器IP> to any port 2525 proto tcp
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

- 云厂商安全组是否放行 Relay 端口；
- 弱服务器系统防火墙是否放行；
- 安装时填写的强服务器 IP 是否正确；
- 强服务器是否真的从该公网 IP 出口访问；
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

脚本每次运行会备份：

```text
/etc/postfix/main.cf.bak.<时间戳>
/etc/postfix/master.cf.bak.<时间戳>
```

如果需要回滚，找到对应备份后恢复：

```bash
sudo cp /etc/postfix/main.cf.bak.<时间戳> /etc/postfix/main.cf
sudo cp /etc/postfix/master.cf.bak.<时间戳> /etc/postfix/master.cf
sudo systemctl restart postfix
```

删除 Relay 用户：

```bash
sudo saslpasswd2 -d relay
sudo systemctl restart postfix
```

删除上游 SMTP 密码文件：

```bash
sudo rm -f /etc/postfix/sasl_passwd /etc/postfix/sasl_passwd.db
sudo systemctl restart postfix
```

## 文件结构

```text
smtp-relay-gateway/
  README.md
  scripts/
    install-smtp-relay.sh
  examples/
    env.example
    nodemailer-example.js
    python-send-test.py
```

## 生产建议

- 使用灰云域名 + 正式证书；
- 只允许强服务器 IP 访问 Relay 端口；
- 使用专门的发信账号或 SMTP 专用凭据；
- 邮箱类服务尽量开启 MFA，并使用 App Password/授权码；
- 设置业务侧限流；
- 定期查看 `/var/log/mail.log`；
- 邮件量较大时优先使用 Amazon SES、Mailgun、SendGrid、Postmark、Resend 或服务商官方 API。
