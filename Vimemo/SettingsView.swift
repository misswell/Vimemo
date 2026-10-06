import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: ProjectStore
    @AppStorage("defaultQuality") private var quality = ExportQuality.high.rawValue
    @AppStorage("defaultPreserveDate") private var preserveDate = true
    @AppStorage("defaultPreserveLocation") private var preserveLocation = false
    @AppStorage("defaultMuted") private var muted = false
    @State private var usage = "计算中…"
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
                        tip("为什么最长 3 秒？", "较短片段更适合实况照片。我们把编辑后的输出限制在 3 秒以内；一段长视频可以制作多个片段。")
                        tip("分享为什么有两个文件？", "实况照片由照片和视频配对组成。要保留实况，优先从照片 App 通过 AirDrop 或 iCloud 分享。普通聊天软件可能只发送静态照片。")
                        tip("能设置动态壁纸吗？", "能否作为动态锁屏由 iOS 版本和系统对素材的判断决定，保存为实况照片不保证锁屏动画可用。")
                    }
                }
                VStack(spacing: 9) {
                    Label("离线处理 · 无账号 · 无水印", systemImage: "lock.shield").font(.caption).foregroundStyle(StudioTheme.secondary)
                    Text("Vimemo 实刻 · 1.0.0").font(.system(size: 11, design: .monospaced)).foregroundStyle(StudioTheme.secondary.opacity(0.6))
                }.frame(maxWidth: .infinity).padding(.vertical, 15)
            }.padding(.horizontal, 24)
        }.scrollIndicators(.hidden).task { usage = store.diskUsage }
    }
    private func tip(_ title: String, _ content: String) -> some View {
        VStack(alignment: .leading, spacing: 7) { Text(title).font(.system(size: 13, weight: .medium)); Text(content).font(.system(size: 12)).foregroundStyle(StudioTheme.secondary).lineSpacing(3) }
    }
}
