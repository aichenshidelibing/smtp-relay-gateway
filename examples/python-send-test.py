#!/usr/bin/env python3
import os
import smtplib
import ssl
from email.message import EmailMessage

host = os.environ["SMTP_HOST"]
port = int(os.environ.get("SMTP_PORT", "2525"))
user = os.environ["SMTP_USER"]
password = os.environ["SMTP_PASS"]
mail_from = os.environ["MAIL_FROM_ADDRESS"]
mail_to = os.environ["TEST_TO"]

message = EmailMessage()
message["From"] = mail_from
message["To"] = mail_to
message["Subject"] = "SMTP Relay 测试"
message.set_content("这是一封通过弱服务器 SMTP Relay 发出的测试邮件。")

context = ssl.create_default_context()

# 如果 Relay 使用自签证书且客户端严格校验，可临时取消下面两行注释。
# 生产更推荐使用正式证书，而不是关闭校验。
# context.check_hostname = False
# context.verify_mode = ssl.CERT_NONE

with smtplib.SMTP(host, port, timeout=30) as smtp:
    smtp.ehlo()
    smtp.starttls(context=context)
    smtp.ehlo()
    smtp.login(user, password)
    smtp.send_message(message)

print("sent")
