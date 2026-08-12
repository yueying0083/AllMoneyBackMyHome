import Foundation

public struct QuoteFetchResult: Sendable {
    public let quotes: [SecuritySymbol: Quote]
    public let actualSource: QuoteSource
    public let isUsingFallback: Bool
}

public actor QuoteService {
    private let providers: [QuoteSource: any QuoteProvider]
    private var preferredFailureCount = 0
    private var fallbackActive = false
    private var lastPreferredProbe: Date?

    public init(providers: [any QuoteProvider] = [TencentQuoteProvider(), SinaQuoteProvider()]) {
        self.providers = Dictionary(uniqueKeysWithValues: providers.map { ($0.source, $0) })
    }

    public func fetch(
        symbols: [SecuritySymbol],
        preferred: QuoteSource,
        proxy: ProxyConfiguration,
        now: Date = Date()
    ) async throws -> QuoteFetchResult {
        guard let preferredProvider = providers[preferred],
              let fallbackProvider = providers[preferred.alternate] else {
            throw QuoteProviderError.invalidResponse("行情源未配置")
        }

        if fallbackActive {
            let shouldProbe = lastPreferredProbe.map { now.timeIntervalSince($0) >= 300 } ?? true
            if shouldProbe {
                lastPreferredProbe = now
                do {
                    let quotes = try await preferredProvider.fetch(symbols: symbols, proxy: proxy)
                    fallbackActive = false
                    preferredFailureCount = 0
                    return QuoteFetchResult(quotes: quotes, actualSource: preferred, isUsingFallback: false)
                } catch let error as TransportError {
                    if blocksFailover(error, proxy: proxy) { throw error }
                } catch {
                    // Keep using the fallback until the preferred provider returns valid data.
                }
            }
            let quotes = try await fallbackProvider.fetch(symbols: symbols, proxy: proxy)
            return QuoteFetchResult(quotes: quotes, actualSource: preferred.alternate, isUsingFallback: true)
        }

        do {
            let quotes = try await preferredProvider.fetch(symbols: symbols, proxy: proxy)
            preferredFailureCount = 0
            return QuoteFetchResult(quotes: quotes, actualSource: preferred, isUsingFallback: false)
        } catch let error as TransportError {
            if blocksFailover(error, proxy: proxy) { throw error }
            return try await recordFailureAndFetchFallback(
                error: error,
                symbols: symbols,
                preferred: preferred,
                fallbackProvider: fallbackProvider,
                proxy: proxy,
                now: now
            )
        } catch {
            return try await recordFailureAndFetchFallback(
                error: error,
                symbols: symbols,
                preferred: preferred,
                fallbackProvider: fallbackProvider,
                proxy: proxy,
                now: now
            )
        }
    }

    public func resetFailover() {
        preferredFailureCount = 0
        fallbackActive = false
        lastPreferredProbe = nil
    }

    private func recordFailureAndFetchFallback(
        error: Error,
        symbols: [SecuritySymbol],
        preferred: QuoteSource,
        fallbackProvider: any QuoteProvider,
        proxy: ProxyConfiguration,
        now: Date
    ) async throws -> QuoteFetchResult {
        preferredFailureCount += 1
        guard preferredFailureCount >= 2 else { throw error }
        fallbackActive = true
        lastPreferredProbe = now
        let quotes = try await fallbackProvider.fetch(symbols: symbols, proxy: proxy)
        return QuoteFetchResult(quotes: quotes, actualSource: preferred.alternate, isUsingFallback: true)
    }

    private func blocksFailover(_ error: TransportError, proxy: ProxyConfiguration) -> Bool {
        guard proxy.isEnabled else { return false }
        if case .httpStatus = error { return false }
        return true
    }
}
