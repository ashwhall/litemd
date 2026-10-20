import Cocoa
import Quartz

/// Data-based Quick Look preview: returns rendered HTML, so no web view runs in this process.
final class PreviewProvider: QLPreviewProvider, QLPreviewingController {
    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        let data = try Data(contentsOf: request.fileURL)
        let page = MarkdownRenderer.standalonePage(for: MarkdownRenderer.decode(data).text, fileURL: request.fileURL)
        return QLPreviewReply(dataOfContentType: .html, contentSize: CGSize(width: 900, height: 1000)) { reply in
            reply.stringEncoding = .utf8
            return Data(page.utf8)
        }
    }
}
