# Vimemo 实刻官网

独立静态产品站，部署目标为 https://vimemo.liuguofeng.com/，生产文件直接来自此目录。页面以 HTML、CSS、少量原生 JavaScript、SVG 和本地静态图片组成，没有第三方运行时或统计脚本。

## 内容与素材

- index.html：中文产品介绍、App Store 入口、功能信息、FAQ 与二维码。
- site.css、site.js：响应式版式与移动端导航。
- assets/screenshot-workspace.png、screenshot-drafts.png、screenshot-export.png：App Store 当前版本公开截图。
- assets/workflow-html.png、assets/formats-html.png：从 Marketing/Blog/vimemo-promotional-visuals.html 用 HTML/CSS/SVG 绘制并渲染的介绍图。
- assets/og-cover.png：同一套 HTML/CSS 视觉，用于社交分享预览。
- assets/appstore-qr.svg：由此前验证过的中国区 App Store 链接二维码矩阵绘制的静态 SVG。
- deploy/nginx/vimemo.liuguofeng.com.conf：隔离站点的 Nginx TLS 配置模板，包含 HTTP 跳转和 ACME challenge 路径。

网站只宣传 App Store 当前公开的能力。设备兼容、版本与购买条款均提示以 App Store 页面为准。

## 发布约定

生产目录：/home/wwwroot/vimemo.liuguofeng.com/
Nginx 配置：/etc/nginx/conf.d/vimemo.liuguofeng.com.conf
证书目录：/etc/nginx/ssl/vimemo.liuguofeng.com/

先部署静态文件并创建只监听 HTTP 的 ACME challenge / 跳转配置，再通过 /home/wwwroot/default 执行 HTTP-01 签发。安装证书后启用完整 HTTPS 配置；每次改配置先运行 nginx -t，通过后 reload。服务器现有 acme.sh cron 会定期续期，续期 challenge 仍走同一个 webroot。
