# Vimemo · 实刻

原生 iOS 视频转实况照片工作台。SwiftUI 界面、AVFoundation 编辑与转换、Photos 实况预览和相册保存。最低 iOS 18，支持 iPhone 和 iPad，全部处理在设备本地完成。

## 最新更新（1.0.20）

裁剪片段两端拖柄与选区边框按缩略图条垂直居中；精确裁剪加减按钮缩小为 28 点的普通样式，保留 44 点触控范围。移除「发现更多片段」，使用片段栏加号添加片段。

作品声音统一由预览右下角的扬声器图标控制，取消按钮背景，预览与导出沿用同一草稿设置。移除播放区、导出页和偏好设置里的重复静音开关；批量导出保留各作品自己的静音状态。

封面只在时间轴下方箭头区域拖动，上方竖线不拦截裁剪；短片段两端的触控区域按选区中点分开。LIVE、时长和声音图标固定在预览区域角落，视频按构图比例在区域内居中，9:16 竖屏不再挤压标记。工作台导入封面的点击范围限定在可见卡片内，避免 iPad 的大图透明范围挡住草稿。

示例封面与作品/草稿缩略图共享后台预解码、请求合并及有内存上限的缓存，滚动时复用图片。保留原生 TabView 的液态玻璃及自动收缩、展开。

修复拖动时间轴封面帧时竖线闪烁：封面线使用固定时间轴坐标读取手势，避免自身移动影响拖动距离，连续左右拖动稳定跟随手指；向下拉慢速选帧继续可用。

在「画面」中选择裁剪比例后，可直接拖动预览图片确定裁剪位置；拖动时显示参考网格，自动限制边界。画面跟随手指移动，松手后同步到封面、动态预览与导出，支持旋转、翻转和相册照片封面。原有位置滑杆保留在「精确位置」中；按住预览实况继续可用。预览右下角的扬声器图标统一控制作品预览和导出声音，并随草稿保存。

制作与导出页逐片段显示真实处理后的封面，轻点播放当前裁剪、构图、调色和倍速效果，长按放大预览；静态照片显示所选封面，GIF 预览不播放声音。最近添加列表移除每个草稿右上角的导出按钮，导出统一使用编辑器底部入口或批量制作。

## 现在可以做什么

- 从系统照片选择器一次导入最多 20 个视频，也可从文件 App 多选导入；单个视频导入后直接进入编辑器。
- 拖动时间轴裁剪和移动片段；逐帧调整入点、出点和封面；通过实际帧的清晰度比较自动选择封面。
- 独立封面选择界面：从片段内任意一帧挑选，或选择相册照片，封面随草稿保存。
- 一次性购买后，设置中可开启“不限制时长”，选择整段视频；默认仍为 3 秒，关闭开关时自动缩短已有片段。
- 每个视频最多保存 20 个片段，使用片段栏的加号添加。
- 原始、9:16、1:1、4:3、16:9 构图，四档旋转，水平翻转，裁剪中心调整。
- 六种色彩风格，曝光、对比度与饱和度调整；照片与动态预览共享相同参数。
- 0.5×、1×、1.5×、2× 播放速度；保留声音或静音。
- Live Photo、MOV 视频、GIF 动图、JPG 照片四种输出；实况、视频与照片支持原始尺寸 / 1080p / 720p。
- GIF 支持最大边长 320 / 480 / 640 / 960 / 1280 像素，以及 5 / 10 / 12 / 15 / 20 / 24 / 30 帧/秒；选择随草稿保存。
- 多视频、多片段顺序制作，进度显示、取消；已完成结果保留，未完成输出清理。
- 保存到照片图库，或在本机作品中预览、再次保存、分享和存储到文件。
- Apple Music 风格的影像工作台、照片导入封面及自适应草稿网格；草稿支持长按重命名。设置支持跟随系统（默认）、深色和浅色，立即生效并保存选择，覆盖编辑、导出及购买页。原生 TabView 提供统一浮动标签栏与滚动收起；封面操作采用原生液态玻璃；iOS 18–25 使用材质兼容，降低透明度时使用实色底。
- 编辑器固定预览、封面入口和底部工具栏，预览按视频方向和输出比例适配；构图与调色时随时查看效果，精确裁剪按需展开，加减按钮使用小尺寸普通样式，重置前确认。iPad 使用预览与参数双栏布局。
- 导出页支持真实片段预览与长按放大，再选择格式与保存位置，底部固定显示参数摘要和制作按钮；拍摄信息与隐私选项按需展开。
- 草稿默认自动保存，可在设置中关闭；关闭后返回时清理本次编辑文件，已有草稿和导出作品保留。支持重命名、删除、存储占用分类和临时缓存清理。
- 按选择保留导入文件已有的拍摄时间和 GPS；默认关闭位置保留。相册再次保存时也使用作品记录中的信息。

## 免费与收费

3 秒内的实况、MOV、GIF 导出，以及静态照片、视频帧/相册封面和全部编辑功能免费。GIF 的全部尺寸与帧率选项免费。
超过 3 秒的动态导出使用一次性非消耗型应用内购买解锁，不订阅、不按次数收费。美国价格为 0.99 美元，中国大陆为 6 元；其他地区由 Apple 换算，购买界面读取 StoreKit 的实际本地价格。
商品 ID：`com.vimemo.live.unlimited`。购买权益仅来自 StoreKit 验证通过的交易，支持恢复购买与退款后收回权限。旧版长草稿继续保留，未购买时长导出会显示解锁入口，也可免费导出静态照片。
购买页采用海边画面、系统黑白底色、红粉强调色、权益卡片和底部固定购买按钮；价格加载时显示进度，失败时显示持续的错误提示与重试入口。
App Store Connect 商品与价格已配置；首次内购须随应用版本提交 Apple 审核，通过并上架后才能正式收费。GitHub IPA 和真机 Ad Hoc 安装不代表内购已上线。

本机 iOS 26.5 的 StoreKitTest 配置同步受 Apple FB22237318 影响，商品价格和购买交易 UI 测试与交易单元测试在该运行时跳过；iOS 27 模拟器当前将本地交易判为 `invalidDeviceVerification`。相应成功购买/恢复/退款集成测试明确跳过，保留签名验证，不用未验证交易解锁。正式启用收费前须在 TestFlight 沙盒完成成功购买、重装恢复与退款验证。

## 与参考视频对应

参考素材为 21.01 秒屏幕录制，仅用于本地分析，不包含在仓库和应用中。

| 参考视频展示的能力 | Vimemo 实现及扩展 |
| --- | --- |
| 视频预览和实况预览 | 编辑后动态预览，以及系统 PHLivePhotoView 实况播放 |
| 裁剪片段、逐帧选择 | 拖动裁剪、移动整段、入点/出点/封面逐帧调整 |
| 精彩瞬间候选 | 均匀时间候选，加上实际画面清晰度选封面 |
| 裁切画面 | 多种比例、裁剪中心、旋转和翻转 |
| 导出画质 | 三档分辨率，不放大原片，H.264 编码与高质量 JPG |
| 保留时间和位置 | 照片、视频、相册资产及本机作品记录保留已有信息 |
| 相册 / 文件保存 | 相册保存、本机收藏、系统分享和文件保存 |
| 单个片段制作 | 多片段、多视频批量制作，草稿恢复和作品管理 |
| 图片和 GIF 独立导出 | JPG、MOV、GIF、Live Photo 独立输出 |
| — | 六种滤镜、调色、倍速、静音、离线处理、无水印 |

候选片段按时间取样，不声称识别人脸、场景或精彩内容。自动选封面使用拉普拉斯方差和曝光裁切惩罚比较帧清晰度。

## 运行

打开 `Vimemo.xcodeproj`，选择 Vimemo scheme 和 iOS 18 以上设备后运行。项目已设置开发团队 `U8U443D7ZL`；真机需要本机有效的 Apple 开发签名和对应 provisioning profile。若 Bundle ID 被其他账户占用，请改成团队可用的唯一 ID。

工程由 XcodeGen 管理。修改 `project.yml` 后执行：

```sh
xcodegen generate
```

编译模拟器：

```sh
xcodebuild -project Vimemo.xcodeproj -scheme Vimemo \
  -configuration Release -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build
```

编译未签名真机版本：

```sh
xcodebuild -project Vimemo.xcodeproj -scheme Vimemo \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build
```

## 验证

转换测试覆盖真实 Live Photo 配对识别（包含 10 秒实况）、配对标识、封面时刻、相册封面、旧草稿兼容、时长开关、GPS、四种输出、全部 GIF 尺寸/帧率的实际文件、帧数/循环/播放时长、最短片段、GIF 设置草稿兼容、旋转元数据、构图、滤镜预览一致性、倍速/声音、批量队列、草稿恢复、删除独立性、取消和清晰度选择。购买测试覆盖按实际输出时长判定、批量导出拦截、StoreKit 验证交易、权益恢复和退款。

存储测试覆盖默认开启、关闭后编辑不覆盖旧草稿、重新开启保存、未完成导出的输入保护、启动清理、损坏索引保留恢复文件、替换封面回收、拒绝符号链接及无效导入清理。

UI 测试会创建独立的测试库，制作两张实况并保存相册，重启恢复草稿，回看并播放作品；也验证方形构图、旋转、翻转、滤镜、静态照片导出、视频帧和相册封面选择、关闭购买界面继续免费使用，以及旧版长草稿的付费拦截。也验证 GIF 参数选择、本机导出和重启后恢复选择。另验证保存开关、关闭后退出清理、重启后作品保留及重新开启后的草稿恢复。新增固定工具/封面/导出入口、取消重置保持编辑、直接重命名与从草稿编辑器导出流程，并在 iPhone SE 与 iPad mini 上验证。测试生成的相册作品留在模拟器中。

先安装模拟器 app 并授予测试所需的「仅添加」照片权限，然后运行测试：

```sh
xcrun simctl privacy booted grant photos-add com.vimemo.live
xcodebuild -project Vimemo.xcodeproj -scheme Vimemo \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO test
```

`Scripts/verify-audio.swift` 可以在 macOS 上直接编译与运行同一份转换核心，验证四种倍速与静音组合。音频 fixture 来自本项目生成的画面与 440Hz 合成音。

`Scripts/verify-cover-line.swift` 检查模拟器连续左右拖动封面线的录制，逐帧检测短时间反向跳动。运行 `swift Scripts/verify-cover-line.swift recording.mov y0 y1 x0 x1`，坐标为录制中的像素范围，选择覆盖竖线主干且避开文字的区域；修复前相同拖动检测到 285 次反向跳动，修复后为 0 次。

```sh
swiftc -target arm64-apple-macos14.0 -parse-as-library \
  Vimemo/Models.swift Vimemo/MediaProcessor.swift Vimemo/LivePhotoExporter.swift \
  Scripts/verify-audio.swift -o /tmp/vimemo-verify-audio
/tmp/vimemo-verify-audio Vimemo/Resources/Demo.mov build/AudioVerification
```

## 输出和边界

- 默认每个片段经倍速处理后的输出限制为 3 秒。设置中开启“不限制时长”后可选择整段视频；关闭开关会将已有片段缩短到 3 秒输出。长片段制作需要更多时间和空间，系统实况播放及动态壁纸行为由 iOS 决定。
- 相册封面按视频输出比例裁切，并应用当前画面与调色设置；实况的动态部分仍播放所选视频。封面照片不附加自己的拍摄时间或 GPS。
- 「原始尺寸」最大边长 4096；1080p / 720p 最大边长 1920 / 1280，输出为偶数像素。这里是分辨率选项，不保证与原片压缩码率一致。
- 「设置 → 本机存储 → 保存草稿」默认开启。关闭时保留已有草稿的保存版本，本次改动不自动写入草稿；新导入的视频、缩略图和照片封面只用于本次编辑。返回工作台、离开工作台或关闭批量导出窗口时清理不再使用的临时文件。短暂后台切换不会清理正在编辑的内容。
- 导出作品始终保留在作品库，与源草稿独立。导出任务持有输入文件直至结束，缓存清理和删除草稿不会打断当前导出；异常退出留下的无引用文件在下次启动清理。损坏索引和恢复副本对应的文件保守保留，不做自动删除。
- 「清理临时缓存」只移除无引用的应用临时文件；可查看草稿、作品与临时文件占用。替换封面后回收不再使用的旧照片；未保存的临时导入文件不参与备份。相册原片和已保存的相册作品不受影响。
- GIF 循环播放，无声音。导出页选择最大边长 320 / 480 / 640 / 960 / 1280 像素与 5 / 10 / 12 / 15 / 20 / 24 / 30 fps，保留当前构图比例且不放大原片。旧草稿默认 640 像素、12 fps。GIF 以百分之一秒保存帧间隔，非整除帧率交替分配间隔以保持总时长；最后一帧可短于标准间隔。预览按帧解码，避免将长 GIF 全部画面留在内存中。
- Live Photo 由具有相同标识的 JPG 与 MOV 组成，MOV 含封面时刻元数据轨。系统分享配对文件时会出现两个文件；通过照片 App 的 AirDrop / iCloud 分享更适合保留实况身份。
- 拍摄信息只来自视频文件已有元数据；选择器若移除了信息，应用不会编造。动态锁屏动画由 iOS 决定，应用不承诺所有生成实况都能作为动态壁纸。
- 请求照片权限时只请求添加，不要求读取整个图库。相册保存失败时，本机作品仍保留，可以改用文件分享。
- iOS 后台只允许有限执行时间；后台额度用尽时取消剩余队列并保留完成项。没有服务器和后台无限处理服务。
- HDR 输入按当前渲染管线输出 SDR H.264/JPG；不宣称保留 HDR 或原始视频编码。

## 文件结构

- `Vimemo/Models.swift`：草稿、片段、设置、作品。
- `ProjectStore.swift`：本机库、导入、自动保存、批量队列。
- `MediaProcessor.swift` / `PreviewCompositor.swift`：构图、色彩、预览。
- `LivePhotoExporter.swift`：配对照片/视频、音频、GIF、相册保存。
- `FrameAnalysis.swift`：清晰度封面选择。
- `HomeView.swift` / `EditorView.swift` / `TimelineView.swift`：工作台和编辑。
- `CoverPickerView.swift`：视频逐帧与相册照片封面选择。
- `PurchaseStore.swift` / `UnlimitedPurchaseView.swift`：StoreKit 2 购买、恢复、权益验证与长导出权限。
- `ExportViews.swift` / `ClipPlaybackPreview.swift`：制作与导出、真实编辑片段预览及长按放大。
- `GIFPlaybackView.swift` / `HistoryView.swift` / `SettingsView.swift`：GIF 逐帧预览、作品和设置。
- `Scripts/make-demo.swift`：原创海边示例视频和应用图标生成器。

参考录屏只用于分析，未打包进应用。项目无第三方运行时依赖。

## GitHub 发布

源码仓库：[misswell/Vimemo](https://github.com/misswell/Vimemo)。当前源码发布版本为 1.0.20，GitHub tag 为 `v1.0.20`；随附 IPA 的 App 版本为 1.0.11（20），使用 Xcode 27（27A266a）及 iOS 27 SDK 构建。本轮 iPhone / iPad 回归使用本机可用的 iOS 26.3 模拟器运行时；尚未进行 iOS 27 运行时验证。
Release 附带 Apple Distribution 签名的 App Store IPA，仅供 App Store Connect 上传；日常安装请使用下方 TestFlight 邀请。
`build/`、参考录屏截图、个人 Xcode 配置和签名凭据均不纳入 Git。

## TestFlight

1.0.0（1）正式签名包已生成并验证：`build/TestFlight/Export/Vimemo.ipa`。
归档：`build/TestFlight/Vimemo-1.0.0-1.xcarchive`。中文测试说明：`build/TestFlight/WhatToTest.zh-Hans.txt`。
2026-10-06 已上传并处理通过，内部测试状态为 `IN_BETA_TESTING`。测试邀请已发送到 `misswell@foxmail.com`，可通过邀请邮件在 iPhone / iPad 的 TestFlight 安装。
最新内部测试版本为 1.0.11（18），构建 ID `c807ec7b-0775-4bca-9cdf-89f92d82bfe3`，状态 `VALID` / `IN_BETA_TESTING`，已加入现有内部测试组并开启自动通知。包含封面线拖动闪烁修复、裁剪预览拖动、连续封面选帧、按住预览与独立声音开关；整体界面对齐 iOS 27 Apple Music。通过现有邀请在 TestFlight 中覆盖安装，不必先删除应用。TestFlight 内购使用 Apple 沙盒，不实际扣款；商品价格加载失败时可在固定按钮处查看错误并重试。
App Store Connect：[Vimemo 实刻 TestFlight](https://appstoreconnect.apple.com/apps/6819492441/testflight/ios)。
应用 ID：`6819492441`；构建 ID：`54e012e6-b4cc-4c50-a763-8058c9640432`；内部测试组：`58d7d5de-0316-4bf2-a7a5-5acf1387b9d5`。

2026-10-08 已提交 App Store 1.0.11（18）与不限制时长内购审核；提交时状态为 `WAITING_FOR_REVIEW`。本次 GitHub 构建 20 不自动上传 TestFlight，也不替换已提交审核的版本。
