import CCurlShim
import Foundation

public struct HTTPResponse: Sendable, Equatable {
    public let data: Data
    public let statusCode: Int

    public init(data: Data, statusCode: Int) {
        self.data = data
        self.statusCode = statusCode
    }
}

public enum TransportError: LocalizedError, Equatable, Sendable {
    case proxy(String)
    case timeout
    case dns(String)
    case connection(String)
    case tls(String)
    case httpStatus(Int)
    case other(String)

    public var isProxyFailure: Bool {
        if case .proxy = self { return true }
        return false
    }

    public var errorDescription: String? {
        switch self {
        case .proxy(let detail): return "代理连接失败：\(detail)"
        case .timeout: return "连接超时"
        case .dns(let detail): return "DNS 解析失败：\(detail)"
        case .connection(let detail): return "连接失败：\(detail)"
        case .tls(let detail): return "TLS 校验失败：\(detail)"
        case .httpStatus(let status): return "服务器返回 HTTP \(status)"
        case .other(let detail): return "网络请求失败：\(detail)"
        }
    }
}

public protocol NetworkTransport: Sendable {
    func get(url: URL, referer: String, proxy: ProxyConfiguration) async throws -> HTTPResponse
}

public struct CurlTransport: NetworkTransport {
    public init() {}

    public func get(url: URL, referer: String, proxy: ProxyConfiguration) async throws -> HTTPResponse {
        let validated = try proxy.validated()
        return try await Task.detached(priority: .utility) {
            let proxyType = validated.isEnabled ? validated.scheme.curlValue : 0
            let result = url.absoluteString.withCString { urlCString in
                referer.withCString { refererCString in
                    validated.host.withCString { proxyCString in
                        ambh_http_get(urlCString, refererCString, proxyType, proxyCString, Int32(validated.port), 10, 15)
                    }
                }
            }
            defer { ambh_http_result_free(result) }

            let message = result.error_message == nil ? "未知错误" : String(cString: result.error_message)
            guard result.curl_code == 0 else {
                throw classifyCurlError(
                    code: result.curl_code,
                    message: message,
                    proxyEnabled: validated.isEnabled
                )
            }
            guard (200...299).contains(result.http_status) else {
                throw TransportError.httpStatus(Int(result.http_status))
            }
            let data = result.data.map { Data(bytes: $0, count: result.length) } ?? Data()
            return HTTPResponse(data: data, statusCode: Int(result.http_status))
        }.value
    }
}

private func classifyCurlError(code: Int32, message: String, proxyEnabled: Bool) -> TransportError {
    if proxyEnabled {
        // Proxy resolution, proxy handshake, and connection failures must never fall back to direct.
        switch code {
        case 5, 7, 28, 35, 56, 60, 67, 97: return .proxy(message)
        default: break
        }
    }
    switch code {
    case 6: return .dns(message)
    case 7: return .connection(message)
    case 28: return .timeout
    case 35, 51, 58, 59, 60, 77, 80, 82, 83, 90, 91: return .tls(message)
    default: return .other(message)
    }
}
