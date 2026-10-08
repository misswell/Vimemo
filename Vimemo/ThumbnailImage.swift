import SwiftUI

struct ThumbnailImage: View {
    var url: URL
    var maxPixelSize = 1024
    @State private var image: UIImage?
    private struct Request: Hashable { let url: URL; let maxPixelSize: Int }

    var body: some View {
        GeometryReader { geometry in
            Group {
                if let image { Image(uiImage: image).resizable().scaledToFill() }
                else { StudioTheme.raised.overlay { Image(systemName: "photo").foregroundStyle(StudioTheme.secondary) } }
            }.frame(width: geometry.size.width, height: geometry.size.height).clipped()
        }.task(id: Request(url: url, maxPixelSize: maxPixelSize)) {
            let loaded = await ThumbnailLoader.shared.image(for: url, maxPixelSize: maxPixelSize)
            guard !Task.isCancelled else { return }
            image = loaded
        }
    }
}
