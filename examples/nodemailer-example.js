import nodemailer from "nodemailer";

const transporter = nodemailer.createTransport({
  host: process.env.SMTP_HOST,
  port: Number(process.env.SMTP_PORT || 2525),
  secure: false,
  requireTLS: true,
  auth: {
    user: process.env.SMTP_USER,
    pass: process.env.SMTP_PASS,
  },
  // 如果 Relay 使用自签证书且客户端严格校验，可临时打开下面配置。
  // 生产更推荐使用正式证书，而不是关闭校验。
  // tls: { rejectUnauthorized: false },
});

await transporter.sendMail({
  from: process.env.MAIL_FROM_ADDRESS,
  to: process.env.TEST_TO,
  subject: "SMTP Relay 测试",
  text: "这是一封通过 SMTP 中继服务器发出的测试邮件。",
});

console.log("sent");
