import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var purchases: PurchaseStore
    @AppStorage("defaultQuality") private var quality = ExportQuality.high.rawValue
    @AppStorage("defaultPreserveDate") private var preserveDate = true
    @AppStorage("defaultPreserveLocation") private var preserveLocation = false
    @AppStorage("defaultMuted") private var muted = false
    @AppStorage("unlimitedDuration") private var unlimitedDuration = false
    @State private var usage = "计算中…"
    @State private var showPurchase = false
    @State private var showRestoreResult = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("按你的习惯").font(.system(size: 30, weight: .bold)).padding(.top, 22)
                Text("给下一段回忆，设好默认选项。").font(.subheadline).foregroundStyle(StudioTheme.secondary)
                StudioCard {
                    VStack(alignment: .leading, spacing: 20) {
                        SectionLabel(title: "新视频的默认设置")
                        Picker("输出尺寸", selection: $quality) { ForEach(ExportQuality.allCases) { Text($0.title).tag($0.rawValue) } }.font(.subheadline)
                        Toggle("保留拍摄时间", isOn: $preserveDate)
                        Toggle("保留位置", isOn: $preserveLocation)
                        Toggle("静音导出", isOn: $muted)
                    }.font(.system(size: 14))
                }
                StudioCard {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionLabel(title: "片段时长", detail: purchases.hasUnlimited ? "已解锁" : "一次性购买")
                        Toggle("不限制时长", isOn: Binding(get: { unlimitedDuration }, set: { enabled in
                            if enabled && !purchases.hasUnlimited { showPurchase = true }
                            else { unlimitedDuration = enabled }
                        })).accessibilityIdentifier("unlimitedDuration")
                        if !purchases.hasUnlimited {
                            Button("解锁不限制时长") { showPurchase = true }.accessibilityIdentifier("unlockUnlimited")
                            Text("仅超过 3 秒的动态导出需要购买。3 秒内导出、静态照片和全部编辑功能免费。")
                                .font(.caption).foregroundStyle(StudioTheme.secondary)
                        }
                        Button(purchases.busy ? "正在恢复…" : "恢复购买") {
                            Task { await purchases.restore(); showRestoreResult = true }
                        }.disabled(purchases.busy).font(.caption).accessibilityIdentifier("settingsRestorePurchase")
                        Text("开启后可选择整段视频，已有草稿也可延长。关闭后，超过 3 秒的片段会缩短到 3 秒。长片段需要更多时间和存储空间，系统实况播放与动态壁纸效果由 iOS 决定。")
                            .font(.caption).foregroundStyle(StudioTheme.secondary)
                    }.font(.system(size: 14))
                }
                StudioCard {
                    VStack(alignment: .leading, spacing: 16) {
                        SectionLabel(title: "本机存储", detail: usage)
                        Text("\(store.projects.count) 个草稿 · \(store.exports.count) 个作品").font(.subheadline)
                        Text("长按工作台的草稿或收藏中的作品可删除本机文件。相册中的原视频和已保存作品不会随之删除。").font(.caption).foregroundStyle(StudioTheme.secondary)
                    }
                }
                StudioCard {
                    VStack(alignment: .leading, spacing: 18) {
                        SectionLabel(title: "关于实况")
                        tip("怎样播放？", "保存到照片 App 后，打开实况照片并长按。应用内也可以在作品预览中播放。")
                        tip("怎样制作长片段？", "默认输出最长 3 秒。开启「不限制时长」后，在编辑器选择「使用整段视频」或拖动裁剪两端，自行决定长度。")
                        tip("怎样选封面？", "在编辑器点击「选择封面」，逐帧挑选视频画面，或从相册选择一张照片。自选照片会按视频输出比例裁切。")
                        tip("分享为什么有两个文件？", "实况照片由照片和视频配对组成。要保留实况，优先从照片 App 通过 AirDrop 或 iCloud 分享。普通聊天软件可能只发送静态照片。")
                        tip("能设置动态壁纸吗？", "能否作为动态锁屏由 iOS 版本和系统对素材的判断决定，保存为实况照片不保证锁屏动画可用。")
                    }
                }
                VStack(spacing: 9) {
                    Label("离线处理 · 无账号 · 无水印", systemImage: "lock.shield").font(.caption).foregroundStyle(StudioTheme.secondary)
                    Text("Vimemo 实刻 · \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")").font(.system(size: 11, design: .monospaced)).foregroundStyle(StudioTheme.secondary.opacity(0.6))
                }.frame(maxWidth: .infinity).padding(.vertical, 15)
            }.padding(.horizontal, 24)
        }.scrollIndicators(.hidden).task { usage = store.diskUsage }
            .onChange(of: unlimitedDuration) { _, enabled in store.setUnlimitedDuration(enabled) }
            .sheet(isPresented: $showPurchase) {
                UnlimitedPurchaseView { unlimitedDuration = true }
            }
            .alert("恢复购买", isPresented: $showRestoreResult) {
                Button("好", role: .cancel) {}
            } message: { Text(purchases.message ?? "已恢复不限制时长。") }
    }
    private func tip(_ title: String, _ content: String) -> some View {
        VStack(alignment: .leading, spacing: 7) { Text(title).font(.system(size: 13, weight: .medium)); Text(content).font(.system(size: 12)).foregroundStyle(StudioTheme.secondary).lineSpacing(3) }
    }
}
