import Foundation
import os

private let persistenceLogger = Logger(subsystem: "com.ambh.menubar", category: "persistence")

public struct PersistedState: Codable, Equatable, Sendable {
    public var watchlist: [WatchlistItem]
    public var preferredSource: QuoteSource
    public var proxy: ProxyConfiguration
    public var cachedQuotes: [Quote]
    public var priceRefreshInterval: PriceRefreshInterval
    public var chartRefreshInterval: ChartRefreshInterval
    public var cachedIntradaySeries: [CachedIntradaySeries]

    public init(
        watchlist: [WatchlistItem],
        preferredSource: QuoteSource,
        proxy: ProxyConfiguration,
        cachedQuotes: [Quote],
        priceRefreshInterval: PriceRefreshInterval = .sixtySeconds,
        chartRefreshInterval: ChartRefreshInterval = .fiveMinutes,
        cachedIntradaySeries: [CachedIntradaySeries] = []
    ) {
        self.watchlist = watchlist
        self.preferredSource = preferredSource
        self.proxy = proxy
        self.cachedQuotes = cachedQuotes
        self.priceRefreshInterval = priceRefreshInterval
        self.chartRefreshInterval = chartRefreshInterval
        self.cachedIntradaySeries = cachedIntradaySeries
    }

    private enum CodingKeys: String, CodingKey {
        case watchlist, preferredSource, proxy, cachedQuotes
        case priceRefreshInterval, chartRefreshInterval, cachedIntradaySeries
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        watchlist = try container.decode([WatchlistItem].self, forKey: .watchlist)
        preferredSource = try container.decode(QuoteSource.self, forKey: .preferredSource)
        proxy = try container.decode(ProxyConfiguration.self, forKey: .proxy)
        cachedQuotes = try container.decode([Quote].self, forKey: .cachedQuotes)
        priceRefreshInterval = try container.decodeIfPresent(PriceRefreshInterval.self, forKey: .priceRefreshInterval) ?? .sixtySeconds
        chartRefreshInterval = try container.decodeIfPresent(ChartRefreshInterval.self, forKey: .chartRefreshInterval) ?? .fiveMinutes
        cachedIntradaySeries = try container.decodeIfPresent([CachedIntradaySeries].self, forKey: .cachedIntradaySeries) ?? []
    }
}

public protocol StatePersistence: Sendable {
    func load() -> PersistedState?
    func save(_ state: PersistedState)
}

public struct UserDefaultsPersistence: StatePersistence, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key = "AMBH.persistedState.v1"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> PersistedState? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(PersistedState.self, from: data)
    }

    public func save(_ state: PersistedState) {
        do {
            defaults.set(try JSONEncoder().encode(state), forKey: key)
        } catch {
            persistenceLogger.error("State encoding failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

public extension PersistedState {
    static func initial() -> PersistedState {
        let shanghai = try! SecuritySymbol(exchange: .shanghai, code: "000001")
        let shenzhen = try! SecuritySymbol(exchange: .shenzhen, code: "399001")
        return PersistedState(
            watchlist: [
                WatchlistItem(symbol: shanghai, displayName: "上证指数"),
                WatchlistItem(symbol: shenzhen, displayName: "深证成指")
            ],
            preferredSource: .tencent,
            proxy: ProxyConfiguration(),
            cachedQuotes: [],
            priceRefreshInterval: .sixtySeconds,
            chartRefreshInterval: .fiveMinutes,
            cachedIntradaySeries: []
        )
    }
}
