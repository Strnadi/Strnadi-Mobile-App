import Foundation

enum ColdStartLinkForwarder {
    @discardableResult
    static func forward(
        _ url: URL?,
        using handler: (URL) -> Void
    ) -> Bool {
        guard let url else {
            return false
        }
        handler(url)
        return true
    }
}
