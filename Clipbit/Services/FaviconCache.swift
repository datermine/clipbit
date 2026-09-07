import AppKit

/// Fetches `/favicon.ico` for web URLs, once per origin. Failures are remembered too.
actor FaviconCache {
    static let shared = FaviconCache()

    private var images: [String: NSImage] = [:]
    private var failures: Set<String> = []
    private var inflight: [String: Task<NSImage?, Never>] = [:]
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 8
        configuration.httpAdditionalHeaders = ["Accept": "image/*"]
        session = URLSession(configuration: configuration)
    }

    func favicon(for url: URL) async -> NSImage? {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty
        else { return nil }

        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.port = url.port
        components.path = "/favicon.ico"
        guard let iconURL = components.url else { return nil }

        let key = iconURL.absoluteString
        if let image = images[key] { return image }
        if failures.contains(key) { return nil }
        if let task = inflight[key] { return await task.value }

        let session = self.session
        let task = Task<NSImage?, Never> {
            guard let result = try? await session.data(from: iconURL),
                  let response = result.1 as? HTTPURLResponse,
                  (200..<300).contains(response.statusCode),
                  result.0.count <= 1_000_000,
                  let image = NSImage(data: result.0),
                  image.isValid
            else { return nil }
            return image
        }
        inflight[key] = task
        let image = await task.value
        inflight[key] = nil

        if let image {
            if images.count >= 200 { images.removeAll() }
            images[key] = image
        } else {
            if failures.count >= 500 { failures.removeAll() }
            failures.insert(key)
        }
        return image
    }
}
