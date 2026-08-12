import AMBHCore
import Combine
import Foundation
import os

private let appLogger = Logger(subsystem: "com.ambh.menubar", category: "quotes")

@MainActor
final class AppViewModel: ObservableObject {
    @Published var watchlist: [WatchlistItem]
    @Published var quotes: [SecuritySymbol: Quote]
    @Published var preferredSource: QuoteSource
    @Published var proxy: ProxyConfiguration
    @Published var priceRefreshInterval: PriceRefreshInterval
    @Published var chartRefreshInterval: ChartRefreshInterval
    @Published var addCode = ""
    @Published var errorMessage: String?
    @Published var statusMessage = "正在载入行情..."
    @Published var isRefreshing = false
    @Published var isAdding = false
    @Published var isTestingProxy = false
    @Published var currentIndex = 0
    @Published var intradayPoints: [SecuritySymbol: [IntradayPoint]] = [:]
    @Published var loadingChartSymbols: Set<SecuritySymbol> = []
    @Published var chartErrors: [SecuritySymbol: String] = [:]
    private var chartFetchedAt: [SecuritySymbol: Date] = [:]

    private let persistence: StatePersistence
    private let service: QuoteService
    private let intradayProvider: TencentIntradayProvider
    private let schedule: MarketSchedule
    private var appliedProxy: ProxyConfiguration
    private var priceRefreshTask: Task<Void, Never>?
    private var chartRefreshTask: Task<Void, Never>?
    private var rotationTask: Task<Void, Never>?
    private var chartLoadingDeadlines: [SecuritySymbol: Task<Void, Never>] = [:]
    private var isRefreshingCharts = false

    init(
        persistence: StatePersistence = UserDefaultsPersistence(),
        service: QuoteService = QuoteService(),
        schedule: MarketSchedule = MarketSchedule(),
        intradayProvider: TencentIntradayProvider = TencentIntradayProvider()
    ) {
        self.persistence = persistence
        self.service = service
        self.schedule = schedule
        self.intradayProvider = intradayProvider
        let state = persistence.load() ?? .initial()
        watchlist = state.watchlist
        preferredSource = state.preferredSource
        proxy = state.proxy
        priceRefreshInterval = state.priceRefreshInterval
        chartRefreshInterval = state.chartRefreshInterval
        appliedProxy = state.proxy
        quotes = Dictionary(uniqueKeysWithValues: state.cachedQuotes.map { ($0.symbol, $0) })
        var chinaCalendar = Calendar(identifier: .gregorian)
        chinaCalendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let todaySeries = state.cachedIntradaySeries.filter { chinaCalendar.isDateInToday($0.fetchedAt) }
        intradayPoints = Dictionary(uniqueKeysWithValues: todaySeries.map { ($0.symbol, $0.points) })
        chartFetchedAt = Dictionary(uniqueKeysWithValues: todaySeries.map { ($0.symbol, $0.fetchedAt) })
        if !quotes.isEmpty { statusMessage = "显示上次保存的行情" }
        DispatchQueue.main.async { [weak self] in
            self?.start()
        }
    }

    var menuBarText: String {
        guard !watchlist.isEmpty else { return "添加股票" }
        let index = min(currentIndex, watchlist.count - 1)
        let item = watchlist[index]
        guard let quote = quotes[item.symbol] else {
            return "\(displayName(for: item)) --"
        }
        return "\(displayName(for: item)) \(formatPrice(quote.price)) \(formatPercent(quote.changePercent))"
    }

    func start() {
        if priceRefreshTask == nil {
            priceRefreshTask = Task { [weak self] in
                guard let self else { return }
                await self.refreshPrices(force: true)
                while !Task.isCancelled {
                    let seconds = self.priceRefreshInterval.seconds
                    do { try await Task.sleep(for: .seconds(seconds)) }
                    catch { break }
                    if self.schedule.isTradingTime(Date()) {
                        await self.refreshPrices(force: false)
                    }
                }
            }
        }
        if chartRefreshTask == nil {
            chartRefreshTask = Task { [weak self] in
                guard let self else { return }
                await self.refreshCharts()
                while !Task.isCancelled {
                    let seconds = self.chartRefreshInterval.seconds
                    do { try await Task.sleep(for: .seconds(seconds)) }
                    catch { break }
                    if self.schedule.isTradingTime(Date()) {
                        await self.refreshCharts()
                    }
                }
            }
        }
        if rotationTask == nil {
            rotationTask = Task { [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(10)) }
                    catch { break }
                    guard let self, !self.watchlist.isEmpty else { continue }
                    self.currentIndex = (self.currentIndex + 1) % self.watchlist.count
                }
            }
        }
    }

    func refreshPrices(force: Bool = true) async {
        guard !isRefreshing, !watchlist.isEmpty else { return }
        if !force && !schedule.isTradingTime(Date()) { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let result = try await service.fetch(
                symbols: watchlist.map(\.symbol),
                preferred: preferredSource,
                proxy: appliedProxy
            )
            for (symbol, quote) in result.quotes { quotes[symbol] = quote }
            let missing = watchlist.count - result.quotes.count
            statusMessage = result.isUsingFallback
                ? "正在使用备用源：\(result.actualSource.displayName)"
                : "数据来源：\(result.actualSource.displayName)"
            if missing > 0 { statusMessage += "，\(missing) 只行情已过期" }
            errorMessage = nil
            persist()
        } catch {
            errorMessage = readable(error)
            statusMessage = "刷新失败，显示最后有效行情"
        }
    }

    func addSymbol() async {
        guard !isAdding else { return }
        isAdding = true
        defer { isAdding = false }
        do {
            let symbol = try SecuritySymbol.parse(addCode)
            guard !watchlist.contains(where: { $0.symbol == symbol }) else {
                errorMessage = "该证券已在自选列表中"
                return
            }
            let provider: any QuoteProvider = preferredSource == .tencent
                ? TencentQuoteProvider()
                : SinaQuoteProvider()
            let result = try await provider.fetch(symbols: [symbol], proxy: appliedProxy)
            guard let quote = result[symbol] else { throw QuoteProviderError.noQuotes }
            watchlist.append(WatchlistItem(symbol: symbol, displayName: quote.name))
            quotes[symbol] = quote
            await loadChart(for: symbol)
            addCode = ""
            errorMessage = nil
            statusMessage = "已添加 \(quote.name)"
            persist()
        } catch {
            errorMessage = readable(error)
        }
    }

    func delete(at offsets: IndexSet) {
        let symbols = offsets.compactMap { watchlist.indices.contains($0) ? watchlist[$0].symbol : nil }
        watchlist.remove(atOffsets: offsets)
        for symbol in symbols {
            quotes.removeValue(forKey: symbol)
            intradayPoints.removeValue(forKey: symbol)
            chartFetchedAt.removeValue(forKey: symbol)
            loadingChartSymbols.remove(symbol)
            chartErrors.removeValue(forKey: symbol)
            chartLoadingDeadlines[symbol]?.cancel()
            chartLoadingDeadlines.removeValue(forKey: symbol)
        }
        currentIndex = watchlist.isEmpty ? 0 : min(currentIndex, watchlist.count - 1)
        persist()
    }

    func move(from offsets: IndexSet, to destination: Int) {
        watchlist.move(fromOffsets: offsets, toOffset: destination)
        persist()
    }

    func moveItem(id: String, direction: Int) {
        guard let index = watchlist.firstIndex(where: { $0.id == id }) else { return }
        let destination = index + direction
        guard watchlist.indices.contains(destination) else { return }
        watchlist.swapAt(index, destination)
        persist()
    }

    func deleteItem(id: String) {
        guard let index = watchlist.firstIndex(where: { $0.id == id }) else { return }
        let symbol = watchlist[index].symbol
        watchlist.remove(at: index)
        quotes.removeValue(forKey: symbol)
        intradayPoints.removeValue(forKey: symbol)
        chartFetchedAt.removeValue(forKey: symbol)
        loadingChartSymbols.remove(symbol)
        chartErrors.removeValue(forKey: symbol)
        chartLoadingDeadlines[symbol]?.cancel()
        chartLoadingDeadlines.removeValue(forKey: symbol)
        currentIndex = watchlist.isEmpty ? 0 : min(currentIndex, watchlist.count - 1)
        persist()
    }

    func setAlias(for id: String, alias: String) {
        guard let index = watchlist.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        watchlist[index].alias = trimmed.isEmpty ? nil : trimmed
        persist()
    }

    func displayName(for item: WatchlistItem) -> String {
        item.preferredName(quoteName: quotes[item.symbol]?.name)
    }

    func loadChart(for symbol: SecuritySymbol) async {
        let hasCache = !(intradayPoints[symbol]?.isEmpty ?? true)
        if !hasCache { beginChartLoading(for: symbol) }
        chartErrors.removeValue(forKey: symbol)
        defer { finishChartLoading(for: symbol) }
        do {
            let points = try await intradayProvider.fetch(symbol: symbol, proxy: appliedProxy)
            intradayPoints[symbol] = points
            chartFetchedAt[symbol] = Date()
            statusMessage = "走势已缓存"
            persist()
        } catch {
            chartErrors[symbol] = readable(error)
            statusMessage = "走势图更新失败"
        }
    }

    func refreshCharts() async {
        await refreshCharts(symbols: watchlist.map(\.symbol))
    }

    func ensureChartsLoaded() async {
        let missing = watchlist.map(\.symbol).filter { intradayPoints[$0]?.isEmpty ?? true }
        guard !missing.isEmpty else { return }
        await refreshCharts(symbols: missing)
    }

    private func refreshCharts(symbols: [SecuritySymbol]) async {
        guard !symbols.isEmpty, !isRefreshingCharts else { return }
        isRefreshingCharts = true
        defer { isRefreshingCharts = false }
        for symbol in symbols { beginChartLoading(for: symbol) }
        let provider = intradayProvider
        let proxy = appliedProxy
        for symbol in symbols {
            do {
                let points = try await provider.fetch(symbol: symbol, proxy: proxy)
                intradayPoints[symbol] = points
                chartFetchedAt[symbol] = Date()
                chartErrors.removeValue(forKey: symbol)
            } catch {
                appLogger.error("Chart failed for \(symbol.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
                chartErrors[symbol] = readable(error)
            }
            finishChartLoading(for: symbol)
        }
        for symbol in symbols { finishChartLoading(for: symbol) }
        if symbols.contains(where: { !(intradayPoints[$0]?.isEmpty ?? true) }) {
            statusMessage = "走势已缓存"
        } else if !symbols.isEmpty {
            statusMessage = "走势图更新失败"
        }
        persist()
    }

    func saveSettings() async {
        do {
            let validated = try normalizedProxyDraft()
            proxy = validated
            appliedProxy = validated
            errorMessage = nil
            persist()
            await service.resetFailover()
            restartRefreshTasks()
        } catch {
            errorMessage = readable(error)
        }
    }

    func sourceChanged() async {
        persist()
        await service.resetFailover()
        await refreshPrices(force: true)
    }

    func testProxy() async {
        guard !isTestingProxy else { return }
        isTestingProxy = true
        defer { isTestingProxy = false }
        do {
            let checked = try normalizedProxyDraft()
            let symbol = try SecuritySymbol(exchange: .shanghai, code: "000001")
            let provider: any QuoteProvider = preferredSource == .tencent
                ? TencentQuoteProvider()
                : SinaQuoteProvider()
            _ = try await provider.fetch(symbols: [symbol], proxy: checked)
            statusMessage = checked.isEnabled ? "代理连接测试成功" : "直连测试成功"
            errorMessage = nil
        } catch {
            errorMessage = readable(error)
        }
    }

    func isStale(_ quote: Quote) -> Bool {
        Date().timeIntervalSince(quote.timestamp) > 15 * 60
    }

    private func persist() {
        persistence.save(PersistedState(
            watchlist: watchlist,
            preferredSource: preferredSource,
            proxy: appliedProxy,
            cachedQuotes: Array(quotes.values),
            priceRefreshInterval: priceRefreshInterval,
            chartRefreshInterval: chartRefreshInterval,
            cachedIntradaySeries: intradayPoints.map { symbol, points in
                CachedIntradaySeries(symbol: symbol, points: points, fetchedAt: chartFetchedAt[symbol] ?? Date())
            }
        ))
    }

    private func restartRefreshTasks() {
        priceRefreshTask?.cancel()
        chartRefreshTask?.cancel()
        priceRefreshTask = nil
        chartRefreshTask = nil
        start()
    }

    private func readable(_ error: Error) -> String {
        if proxy.isEnabled, let transport = error as? TransportError {
            switch transport {
            case .proxy: return transport.localizedDescription
            case .timeout, .dns, .connection, .tls:
                return "代理连接失败：\(transport.localizedDescription)"
            default: break
            }
        }
        return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    private func normalizedProxyDraft() throws -> ProxyConfiguration {
        try proxy.applyingHostSemantics()
    }

    private func beginChartLoading(for symbol: SecuritySymbol) {
        loadingChartSymbols.insert(symbol)
        chartLoadingDeadlines[symbol]?.cancel()
        chartLoadingDeadlines[symbol] = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(15)) }
            catch { return }
            guard let self else { return }
            self.loadingChartSymbols.remove(symbol)
            if self.intradayPoints[symbol]?.isEmpty ?? true {
                self.chartErrors[symbol] = "走势图请求超时"
            }
            self.chartLoadingDeadlines.removeValue(forKey: symbol)
        }
    }

    private func finishChartLoading(for symbol: SecuritySymbol) {
        chartLoadingDeadlines[symbol]?.cancel()
        chartLoadingDeadlines.removeValue(forKey: symbol)
        loadingChartSymbols.remove(symbol)
    }
}

func formatPrice(_ value: Double) -> String {
    if abs(value) >= 1000 { return String(format: "%.2f", value) }
    if abs(value) >= 10 { return String(format: "%.2f", value) }
    return String(format: "%.3f", value)
}

func formatPercent(_ value: Double) -> String {
    String(format: "%+.2f%%", value)
}
