import AMBHCore
import CoreFoundation
import Foundation

@main
struct DirectTestRunner {
    static func main() async throws {
        try testSymbols()
        try testProxy()
        try testParsers()
        try testIntradayAndAlias()
        testSchedule()
        try await testFailover()
        try await testTransportFailure()
        print("All 38 core checks passed")
    }

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
    }

    static func testSymbols() throws {
        let shanghai = try SecuritySymbol.parse("600519")
        let shenzhen = try SecuritySymbol.parse("000001")
        let explicit = try SecuritySymbol.parse("sh000001")
        expect(shanghai.id == "sh600519", "Shanghai mapping")
        expect(shenzhen.id == "sz000001", "Shenzhen mapping")
        expect(explicit.id == "sh000001", "Explicit mapping")
        expect(PersistedState.initial().watchlist.count == 2, "Default indices")
    }

    static func testProxy() throws {
        expect(ProxyScheme.http.curlValue == 1, "HTTP proxy")
        expect(ProxyScheme.https.curlValue == 2, "HTTPS proxy")
        expect(ProxyScheme.socks5.curlValue == 3, "SOCKS5 proxy")
        expect(ProxyScheme.socks5h.curlValue == 4, "SOCKS5H proxy")
        do {
            _ = try ProxyConfiguration(isEnabled: true, host: "", port: 7890).validated()
            fatalError("Empty proxy host accepted")
        } catch is ProxyValidationError {}
        let direct = try ProxyConfiguration(isEnabled: true, host: "  ", port: 7890).applyingHostSemantics()
        let enabled = try ProxyConfiguration(isEnabled: false, host: "127.0.0.1", port: 7890).applyingHostSemantics()
        expect(!direct.isEnabled, "Empty host means direct")
        expect(enabled.isEnabled, "Host enables proxy")
    }

    static func testParsers() throws {
        let tencentSymbol = try SecuritySymbol.parse("600519")
        let tencent = "v_sh600519=\"1~贵州茅台~600519~1344.07~1346.50~0~0~0~0~0~0~0~0~0~0~0~0~0~0~0~0~0~0~0~0~0~0~0~0~0~20260812101815~-2.43~-0.18~\";"
        let tq = try TencentQuoteProvider.parse(data: gbData(tencent), expected: [tencentSymbol])[tencentSymbol]
        expect(tq?.name == "贵州茅台", "Tencent name")
        expect(tq?.price == 1344.07, "Tencent price")
        expect(tq?.changePercent == -0.18, "Tencent percent")

        let sinaSymbol = try SecuritySymbol.parse("000001")
        let sina = "var hq_str_sz000001=\"平安银行,11.260,11.260,11.220,11.290,11.200,11.220,11.230,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,2026-08-12,10:18:15,00\";"
        let sq = try SinaQuoteProvider.parse(data: gbData(sina), expected: [sinaSymbol])[sinaSymbol]
        expect(sq?.name == "平安银行", "Sina name")
        expect(sq?.price == 11.22, "Sina price")
        expect(abs((sq?.change ?? 0) + 0.04) < 0.0001, "Sina change")
    }

    static func testSchedule() {
        let schedule = MarketSchedule()
        expect(schedule.isTradingTime(chinaDate("2026-08-12 10:00:00")), "Morning trading")
        expect(!schedule.isTradingTime(chinaDate("2026-08-12 12:00:00")), "Lunch break")
        expect(!schedule.isTradingTime(chinaDate("2026-08-15 10:00:00")), "Weekend")
    }

    static func testIntradayAndAlias() throws {
        let symbol = try SecuritySymbol.parse("sh000001")
        let json = #"{"data":{"sh000001":{"data":{"data":["0930 3933.55 1 2.0","0931 3929.55 2 3.0"]}}}}"#
        let points = try TencentIntradayProvider.parse(data: Data(json.utf8), symbol: symbol)
        expect(points.count == 2, "Intraday count")
        expect(points[0].minute == "09:30", "Intraday minute")
        expect(points[1].price == 3929.55, "Intraday price")
        let item = WatchlistItem(symbol: symbol, displayName: "上证指数", alias: "上证")
        let roundTrip = try JSONDecoder().decode(WatchlistItem.self, from: JSONEncoder().encode(item))
        expect(roundTrip.alias == "上证", "Alias persistence")
        expect(item.preferredName(quoteName: "上证指数") == "上证", "Alias display priority")
        expect(ChinaTradingSession.minuteOffset(for: "09:30") == 0, "Axis start")
        expect(ChinaTradingSession.minuteOffset(for: "11:30") == 120, "Morning close")
        expect(ChinaTradingSession.minuteOffset(for: "13:00") == 210, "Afternoon open")
        expect(ChinaTradingSession.minuteOffset(for: "15:00") == 330, "Axis end")
        expect(ChinaTradingSession.minuteOffset(for: "09:29") == nil, "Axis bound")
        expect(PriceRefreshInterval.fifteenSeconds.seconds == 15, "Price interval")
        expect(ChartRefreshInterval.tenMinutes.seconds == 600, "Chart interval")
        expect(PersistedState.initial().priceRefreshInterval == .sixtySeconds, "Default price interval")
        expect(PersistedState.initial().chartRefreshInterval == .fiveMinutes, "Default chart interval")
        let legacy = #"{"watchlist":[],"preferredSource":"tencent","proxy":{"isEnabled":false,"scheme":"http","host":"","port":7890},"cachedQuotes":[]}"#
        let legacyState = try JSONDecoder().decode(PersistedState.self, from: Data(legacy.utf8))
        expect(legacyState.chartRefreshInterval == .fiveMinutes, "Legacy interval migration")
        expect(legacyState.cachedIntradaySeries.isEmpty, "Legacy chart cache migration")
        let cache = CachedIntradaySeries(symbol: symbol, points: points, fetchedAt: Date(timeIntervalSince1970: 100))
        let decodedCache = try JSONDecoder().decode(CachedIntradaySeries.self, from: JSONEncoder().encode(cache))
        expect(decodedCache == cache, "Chart cache round trip")
    }

    static func testFailover() async throws {
        let symbol = try SecuritySymbol.parse("600519")
        let primary = MockProvider(source: .tencent, results: [.failure(QuoteProviderError.noQuotes), .failure(QuoteProviderError.noQuotes)])
        let quote = Quote(symbol: symbol, name: "test", price: 1, previousClose: 1, change: 0, changePercent: 0, timestamp: Date(), source: .sina)
        let fallback = MockProvider(source: .sina, results: [.success([symbol: quote])])
        let service = QuoteService(providers: [primary, fallback])
        do { _ = try await service.fetch(symbols: [symbol], preferred: .tencent, proxy: ProxyConfiguration()) } catch {}
        let result = try await service.fetch(symbols: [symbol], preferred: .tencent, proxy: ProxyConfiguration())
        expect(result.isUsingFallback && result.actualSource == .sina, "Provider failover")
    }

    static func testTransportFailure() async throws {
        let symbol = try SecuritySymbol.parse("600519")
        let primary = MockProvider(source: .tencent, results: [.failure(TransportError.proxy("offline")), .failure(TransportError.proxy("offline"))])
        let fallback = MockProvider(source: .sina, results: [])
        let service = QuoteService(providers: [primary, fallback])
        for _ in 0..<2 {
            do {
                _ = try await service.fetch(
                    symbols: [symbol],
                    preferred: .tencent,
                    proxy: ProxyConfiguration(isEnabled: true, host: "127.0.0.1", port: 7890)
                )
            } catch {}
        }
        let fallbackCalls = await fallback.count()
        expect(fallbackCalls == 0, "Transport failure triggered fallback")
    }
}

private actor MockProvider: QuoteProvider {
    nonisolated let source: QuoteSource
    private var results: [Result<[SecuritySymbol: Quote], Error>]
    private var calls = 0

    init(source: QuoteSource, results: [Result<[SecuritySymbol: Quote], Error>]) {
        self.source = source
        self.results = results
    }

    func fetch(symbols: [SecuritySymbol], proxy: ProxyConfiguration) async throws -> [SecuritySymbol: Quote] {
        calls += 1
        guard !results.isEmpty else { throw QuoteProviderError.noQuotes }
        return try results.removeFirst().get()
    }

    func count() -> Int { calls }
}

private func gbData(_ string: String) -> Data {
    let encoding = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
    return string.data(using: String.Encoding(rawValue: encoding))!
}

private func chinaDate(_ value: String) -> Date {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return formatter.date(from: value)!
}
