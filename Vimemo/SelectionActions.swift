import SwiftUI

struct SelectionActions: View {
    let count: Int
    let total: Int
    let identifier: String
    let onSelectAll: () -> Void
    let onDelete: () -> Void
    var exportDisabled = false
    var onExport: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text("已选 \(count) 个").font(.subheadline.weight(.medium))
                    .accessibilityIdentifier("\(identifier)SelectionCount")
                Spacer()
                Button(count == total && total > 0 ? "取消全选" : "全选", action: onSelectAll)
                    .disabled(total == 0).accessibilityIdentifier("\(identifier)SelectAll")
            }
            StudioGlassGroup(spacing: 12) {
                HStack(spacing: 12) {
                    if let onExport {
                        Button(action: onExport) {
                            Label("制作所选", systemImage: "square.stack.3d.up")
                                .frame(maxWidth: .infinity).frame(minHeight: 44)
                        }.studioGlassButton().disabled(count == 0 || exportDisabled)
                            .accessibilityIdentifier("\(identifier)ExportSelected")
                    }
                    Button(role: .destructive, action: onDelete) {
                        Label("删除所选", systemImage: "trash")
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity).frame(minHeight: 44)
                    }.studioGlassButton().tint(.red).disabled(count == 0)
                        .accessibilityIdentifier("\(identifier)DeleteSelected")
                }
            }
        }.font(.subheadline).tint(StudioTheme.accent).foregroundStyle(StudioTheme.ink)
            .padding(.horizontal, 20).padding(.vertical, 12)
            .frame(maxWidth: 1000).frame(maxWidth: .infinity)
            .background(StudioTheme.background)
    }
}
