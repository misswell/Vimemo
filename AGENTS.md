# Vimemo 项目规则

- 原生 iOS SwiftUI 应用，最低 iOS 18；使用 Apple AVFoundation、Photos、Core Image，没有第三方运行时依赖。
- `project.yml` 是工程配置来源；调整 target、资源、权限或 scheme 后运行 `xcodegen generate`。
- 保持视频转换在设备本地。使用 PhotosPicker / 文件选择器导入，照片权限仅请求 `.addOnly`。
- 照片与视频必须配对同一 UUID，视频必须含 `com.apple.quicktime.still-image-time` 定时元数据。任何修改转换核心都要验证系统 PHLivePhoto 能识别配对文件。
- 裁剪、滤镜、旋转、翻转必须在封面、动态预览与最终输出中保持一致。
- 默认实况输出最多 3 秒；设置中的“不限制时长”允许选择源视频内任意长度，适用于已有草稿和新导入。更改倍速时按当前时长策略归一化片段；关闭开关时将已有片段缩短至 3 秒输出。仅保留源文件已有且用户选择保留的拍摄信息。
- 封面支持视频逐帧选择与 PhotosPicker 相册照片；照片拷贝至草稿目录，封面预览和输出共享裁剪、旋转、翻转与调色管线。旧草稿缺少新增可选字段时继续使用默认 3 秒与视频封面。
- UI 测试用 DEBUG 下的 `--test-library <UUID>` 创建独立库，不能清空用户草稿。`--demo-editor` 可进入原创示例编辑器。
- 正式资源不包含用户提供的参考录屏或测试音频；`VimemoTests/Fixtures/AudioFixture.mov` 只属于测试 target。
- 构建产物放在 `build/`；交付产物保存到 `build/Products/Simulator/Vimemo.app` 和 `build/Products/iOS/Vimemo.app`。后者无签名时不能直接安装到真机。
- GitHub 远端：`https://github.com/misswell/Vimemo.git`，主分支 `main`。改动验证通过后自动提交、推送，创建新的 patch tag 和正式 GitHub Release，不覆盖既有 tag；Release 附带正式签名 IPA。`build/`、`Reference/` 和签名凭据保持忽略。
- GitHub 首次发布版本为 1.0.1（2），tag `v1.0.1`；与既有 TestFlight 1.0.0（1）分开记录。推送源码和创建 GitHub Release 不自动重复上传 TestFlight。
- 不把 Apple 密码、签名私钥或 provisioning 凭据写入仓库。当前开发团队：`U8U443D7ZL`。
- TestFlight：应用 ID `6819492441`，名称 `Vimemo 实刻`，Bundle ID `com.vimemo.live`，开发者资源 ID `B2FH899KC9`；复用证书 `L4SC3D834Q`（Apple Distribution，2027-07-20 到期）和 profile `BM6L3P6PT6` / `Vimemo App Store`。正式签名归档与 IPA 已验证；内部测试组 ID `58d7d5de-0316-4bf2-a7a5-5acf1387b9d5`。
- 正式上传产物：`build/TestFlight/Vimemo-1.0.0-1.xcarchive`、`build/TestFlight/Export/Vimemo.ipa`。`build/TestFlight/ExportOptions.plist` 使用手动签名；版本与 build 分别取 `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`。上传前核对 IPA 内 Info.plist 的实际版本。
- TestFlight 中文测试说明保存在 `build/TestFlight/WhatToTest.zh-Hans.txt`。应用使用 iOS、简体中文、Bundle ID `com.vimemo.live`、SKU `VIMEMO-IOS-001`；先查询已有 builds，防止重复上传同一版本号。
- 2026-10-06 已完成首次 TestFlight 发布：1.0.0（1），构建 ID `54e012e6-b4cc-4c50-a763-8058c9640432`，处理状态 `VALID`，内部状态 `IN_BETA_TESTING`；中文说明已写入，`misswell@foxmail.com` 已加入内部组并获得邀请。测试者 ID `f12b8d21-7e69-4af8-b0b1-6d3bf08675f6`。后续上传递增 build number，复用现有内部组和测试者，不重复创建或发送邀请。
- 需显示 macOS GUI 时优先使用 AgentSpace。后台会话不可用时先说明，再使用命令行或明确说明的回退方式。
