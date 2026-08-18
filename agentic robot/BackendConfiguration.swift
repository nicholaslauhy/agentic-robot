import Foundation

enum BackendConfiguration {
    private static let infoPlistKey = "HTXBackendBaseURL"
    private static let environmentKey = "HTX_BACKEND_BASE_URL"

    static var baseURL: URL? {
        let environmentValue = ProcessInfo.processInfo.environment[environmentKey]
        let plistValue = Bundle.main.object(forInfoDictionaryKey: infoPlistKey) as? String

        for rawValue in [environmentValue, plistValue].compactMap({ $0 }) {
            if let url = normalizedBaseURL(rawValue) {
                return url
            }
        }

        return nil
    }

    static func endpointURL(
        path: String,
        queryItems: [URLQueryItem] = []
    ) -> URL? {
        guard let baseURL,
              var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }

        let cleanPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var basePath = components.path
        if basePath.isEmpty {
            basePath = "/"
        } else if !basePath.hasSuffix("/") {
            basePath += "/"
        }
        components.path = basePath + cleanPath
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        return components.url
    }

    private static func normalizedBaseURL(_ rawValue: String) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              components.host != nil else {
            return nil
        }

        components.query = nil
        components.fragment = nil
        while components.path.count > 1, components.path.hasSuffix("/") {
            components.path.removeLast()
        }
        return components.url
    }
}
