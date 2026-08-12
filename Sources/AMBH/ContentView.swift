import AMBHCore
import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var model: AppViewModel
    @State private var page = Page.quotes
    @State private var isEditingList = false

    private enum Page {
        case quotes
        case settings
    }

    var body: some View {
        VStack(spacing: 0) {
            if page == .quotes { quotesView } else { settingsView }
            Divider()
            footer
        }
        .frame(width: 315, height: 232)
    }

    private var quotesView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                TextField("股票代码", text: $model.addCode)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await model.addSymbol() } }
                iconButton("plus", help: "添加自选", disabled: model.isAdding || model.addCode.trimmingCharacters(in: .whitespaces).isEmpty) {
                    Task { await model.addSymbol() }
                }
                iconButton(isEditingList ? "checkmark" : "pencil", help: isEditingList ? "完成编辑" : "编辑列表", disabled: model.watchlist.isEmpty) {
                    isEditingList.toggle()
                }
                iconButton("arrow.clockwise", help: "刷新行情", disabled: model.isRefreshing) {
                    Task { await model.refreshPrices(force: true) }
                }
            }
            .padding(10)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(model.watchlist.enumerated()), id: \.element.id) { index, item in
                        if isEditingList {
                            EditWatchlistRow(
                                item: item,
                                officialName: model.quotes[item.symbol]?.name ?? item.displayName ?? item.symbol.code,
                                canMoveUp: index > 0,
                                canMoveDown: index < model.watchlist.count - 1,
                                onAliasChange: { model.setAlias(for: item.id, alias: $0) },
                                onMoveUp: { model.moveItem(id: item.id, direction: -1) },
                                onMoveDown: { model.moveItem(id: item.id, direction: 1) },
                                onDelete: { model.deleteItem(id: item.id) }
                            )
                        } else {
                            QuoteRow(
                                name: model.displayName(for: item),
                                item: item,
                                quote: model.quotes[item.symbol],
                                isStale: model.quotes[item.symbol].map(model.isStale) ?? true,
                                points: model.intradayPoints[item.symbol] ?? [],
                                isLoadingChart: model.loadingChartSymbols.contains(item.symbol),
                                chartFailed: model.chartErrors[item.symbol] != nil
                            )
                        }
                        if index < model.watchlist.count - 1 {
                            Divider()
                        }
                    }
                }
                .padding(.horizontal, 10)
            }

            if model.watchlist.isEmpty {
                Text("添加股票后，价格会显示在菜单栏")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding()
            }

        }
        .task {
            model.start()
            await model.ensureChartsLoaded()
        }
    }

    private var settingsView: some View {
        VStack(spacing: 0) {
            HStack {
                Text("设置")
                    .font(.headline)
                Spacer()
            }
            .padding(10)

            Divider()

            ScrollView {
                VStack(spacing: 0) {
                    SettingsRow(title: "行情源") {
                        Picker("", selection: $model.preferredSource) {
                            ForEach(QuoteSource.allCases, id: \.self) { Text($0.displayName).tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 96, alignment: .trailing)
                        .onChange(of: model.preferredSource) { _ in
                            Task { await model.sourceChanged() }
                        }
                    }

                    Divider().padding(.leading, 10)

                    SettingsRow(title: "价格刷新") {
                        Picker("", selection: $model.priceRefreshInterval) {
                            ForEach(PriceRefreshInterval.allCases, id: \.self) { Text($0.displayName).tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 96, alignment: .trailing)
                    }

                    Divider().padding(.leading, 10)

                    SettingsRow(title: "走势刷新") {
                        Picker("", selection: $model.chartRefreshInterval) {
                            ForEach(ChartRefreshInterval.allCases, id: \.self) { Text($0.displayName).tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 96, alignment: .trailing)
                    }

                    Divider().padding(.leading, 10)

                    SettingsRow(title: "代理") {
                        HStack(spacing: 5) {
                            Picker("", selection: $model.proxy.scheme) {
                                ForEach(ProxyScheme.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                            }
                            .labelsHidden()
                            .frame(width: 68)

                            TextField("IP", text: $model.proxy.host)
                                .textFieldStyle(.roundedBorder)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 78)

                            TextField("端口", value: $model.proxy.port, format: .number.grouping(.never))
                                .textFieldStyle(.roundedBorder)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 58)
                        }
                        .frame(width: 214, alignment: .trailing)
                    }
                }
            }

            Spacer()
        }
    }

    private var footer: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(model.errorMessage == nil ? Color.green : Color.orange)
                .frame(width: 7, height: 7)
            Text(model.errorMessage ?? model.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 4)
            if page == .settings {
                Button {
                    Task { await model.testProxy() }
                } label: {
                    Image(systemName: "network")
                }
                .buttonStyle(.borderless)
                .help("测试连接")
                .disabled(model.isTestingProxy)

                Button {
                    Task { await model.saveSettings() }
                } label: {
                    Image(systemName: "checkmark.circle")
                }
                .buttonStyle(.borderless)
                .help("保存并应用")
                .keyboardShortcut(.defaultAction)
            }
            Button {
                if page == .quotes {
                    isEditingList = false
                    page = .settings
                } else {
                    page = .quotes
                }
            } label: {
                Image(systemName: page == .quotes ? "gearshape" : "arrow.left")
            }
            .buttonStyle(.borderless)
            .help(page == .quotes ? "设置" : "返回自选")
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.borderless)
            .help("退出 AMBH")
        }
        .padding(9)
        .frame(minHeight: 36)
    }

    private func iconButton(_ icon: String, help: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon) }
            .help(help)
            .disabled(disabled)
    }
}

private struct SettingsRow<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.callout)
                .frame(width: 72, alignment: .leading)
            content
                .frame(width: 214, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .frame(height: 38)
    }
}

private struct QuoteRow: View {
    let name: String
    let item: WatchlistItem
    let quote: Quote?
    let isStale: Bool
    let points: [IntradayPoint]
    let isLoadingChart: Bool
    let chartFailed: Bool

    var body: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name).fontWeight(.medium).lineLimit(1)
                HStack(spacing: 4) {
                    Text(item.symbol.providerCode)
                    if isStale { Text("已过期") }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .frame(width: 72, alignment: .leading)

            InlineIntradayChart(
                points: points,
                previousClose: quote?.previousClose,
                isLoading: isLoadingChart,
                failed: chartFailed
            )
            .frame(maxWidth: .infinity)
            .layoutPriority(1)

            if let quote {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(formatPrice(quote.price))
                        .font(.system(.body, design: .monospaced).weight(.semibold))
                    Text(formatPercent(quote.changePercent))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(quote.change > 0 ? Color.red : quote.change < 0 ? Color.green : Color.secondary)
                }
                .frame(width: 66, alignment: .trailing)
            } else {
                Text("--").foregroundStyle(.secondary).frame(width: 66, alignment: .trailing)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
}

private struct EditWatchlistRow: View {
    let item: WatchlistItem
    let officialName: String
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onAliasChange: (String) -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onDelete: () -> Void
    @State private var alias: String

    init(item: WatchlistItem, officialName: String, canMoveUp: Bool, canMoveDown: Bool, onAliasChange: @escaping (String) -> Void, onMoveUp: @escaping () -> Void, onMoveDown: @escaping () -> Void, onDelete: @escaping () -> Void) {
        self.item = item
        self.officialName = officialName
        self.canMoveUp = canMoveUp
        self.canMoveDown = canMoveDown
        self.onAliasChange = onAliasChange
        self.onMoveUp = onMoveUp
        self.onMoveDown = onMoveDown
        self.onDelete = onDelete
        _alias = State(initialValue: item.alias ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(officialName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                Text(item.symbol.providerCode).font(.caption2).foregroundStyle(.tertiary)
            }
            HStack(spacing: 6) {
                TextField("别名（留空使用原名）", text: $alias)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { onAliasChange(alias) }
                    .onDisappear { onAliasChange(alias) }
                compactButton("arrow.up", help: "上移", disabled: !canMoveUp, action: onMoveUp)
                compactButton("arrow.down", help: "下移", disabled: !canMoveDown, action: onMoveDown)
                compactButton("trash", help: "删除", role: .destructive, action: onDelete)
            }
        }
        .padding(.vertical, 4)
    }

    private func compactButton(_ icon: String, help: String, disabled: Bool = false, role: ButtonRole? = nil, action: @escaping () -> Void) -> some View {
        Button(role: role, action: action) { Image(systemName: icon) }
            .buttonStyle(.borderless)
            .help(help)
            .disabled(disabled)
    }
}

private struct InlineIntradayChart: View {
    let points: [IntradayPoint]
    let previousClose: Double?
    let isLoading: Bool
    let failed: Bool

    var body: some View {
        VStack(spacing: 1) {
            if isLoading {
                ProgressView().controlSize(.mini).frame(maxHeight: .infinity)
            } else if failed || points.isEmpty {
                Text(failed ? "走势不可用" : "--")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(maxHeight: .infinity)
            } else {
                FixedSessionChart(points: points, previousClose: previousClose)
                    .frame(height: 30)
                HStack {
                    Text("9:30")
                    Spacer()
                    Text("15:00")
                }
                .font(.system(size: 7))
                .foregroundStyle(.tertiary)
            }
        }
        .frame(height: 42)
    }
}

private struct FixedSessionChart: View {
    let points: [IntradayPoint]
    let previousClose: Double?

    var body: some View {
        Canvas { context, size in
            guard points.count > 1 else { return }
            let prices = points.map(\.price) + (previousClose.map { [$0] } ?? [])
            guard let rawMin = prices.min(), let rawMax = prices.max() else { return }
            let center = previousClose ?? (rawMin + rawMax) / 2
            let radius = max(rawMax - center, center - rawMin, 0.01)
            let minimum = center - radius
            let maximum = center + radius

            func y(_ price: Double) -> CGFloat {
                size.height * CGFloat(1 - (price - minimum) / (maximum - minimum))
            }

            if let previousClose {
                var baseline = Path()
                baseline.move(to: CGPoint(x: 0, y: y(previousClose)))
                baseline.addLine(to: CGPoint(x: size.width, y: y(previousClose)))
                context.stroke(baseline, with: .color(.secondary.opacity(0.35)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }

            var pricePath = Path()
            var hasPoint = false
            for point in points {
                guard let offset = ChinaTradingSession.minuteOffset(for: point.minute) else { continue }
                let x = size.width * CGFloat(offset) / CGFloat(ChinaTradingSession.tradingDuration)
                let coordinate = CGPoint(x: x, y: y(point.price))
                hasPoint ? pricePath.addLine(to: coordinate) : pricePath.move(to: coordinate)
                hasPoint = true
            }
            let lastPrice = points.last?.price ?? center
            let color: Color = lastPrice >= center ? .red : .green
            context.stroke(pricePath, with: .color(color), style: StrokeStyle(lineWidth: 1.2, lineJoin: .round))
        }
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

}
