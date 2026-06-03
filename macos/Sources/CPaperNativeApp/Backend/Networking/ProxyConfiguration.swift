import Foundation

struct ProxyConfiguration: Equatable, Sendable {
    let url: URL?

    init(url: URL?) {
        self.url = url
    }

    init(rawValue: String?) {
        guard
            let rawValue,
            !rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            let url = URL(string: rawValue)
        else {
            self.url = nil
            return
        }
        self.url = url
    }

    var isEnabled: Bool {
        url != nil
    }

    func applying(to configuration: URLSessionConfiguration) -> URLSessionConfiguration {
        guard let proxyDictionary else { return configuration }
        configuration.connectionProxyDictionary = proxyDictionary
        return configuration
    }

    var proxyDictionary: [AnyHashable: Any]? {
        guard let url, let host = url.host else { return nil }
        let port = url.port ?? defaultPort(for: url.scheme)
        var dictionary: [AnyHashable: Any] = [:]

        switch url.scheme?.lowercased() {
        case "http":
            dictionary["HTTPEnable"] = 1
            dictionary["HTTPProxy"] = host
            dictionary["HTTPPort"] = port
        case "https":
            dictionary["HTTPSEnable"] = 1
            dictionary["HTTPSProxy"] = host
            dictionary["HTTPSPort"] = port
        case "socks", "socks5":
            dictionary["SOCKSEnable"] = 1
            dictionary["SOCKSProxy"] = host
            dictionary["SOCKSPort"] = port
        default:
            dictionary["HTTPEnable"] = 1
            dictionary["HTTPProxy"] = host
            dictionary["HTTPPort"] = port
            dictionary["HTTPSEnable"] = 1
            dictionary["HTTPSProxy"] = host
            dictionary["HTTPSPort"] = port
        }

        if let user = url.user?.removingPercentEncoding, !user.isEmpty {
            dictionary["HTTPProxyUsername"] = user
            dictionary["HTTPSProxyUsername"] = user
            dictionary["SOCKSUser"] = user
        }
        if let password = url.password?.removingPercentEncoding, !password.isEmpty {
            dictionary["HTTPProxyPassword"] = password
            dictionary["HTTPSProxyPassword"] = password
            dictionary["SOCKSPassword"] = password
        }

        return dictionary
    }

    private func defaultPort(for scheme: String?) -> Int {
        switch scheme?.lowercased() {
        case "https":
            443
        case "socks", "socks5":
            1080
        default:
            80
        }
    }
}
