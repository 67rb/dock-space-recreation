import AppKit
import SwiftUI

struct StockTile: View {
    @ObservedObject var store: StockStore
    let isCompact: Bool
    @State private var showingPopover = false

    private var tint: Color {
        guard let quote = store.quote else { return .white.opacity(0.62) }
        return quote.isPositive ? Color(red: 0.27, green: 0.83, blue: 0.54) : Color(red: 1.0, green: 0.35, blue: 0.38)
    }

    var body: some View {
        Button { showingPopover.toggle() } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text(store.quote?.symbol ?? store.symbol)
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.67))
                            .lineLimit(1)
                        Circle().fill(tint).frame(width: 4, height: 4)
                    }
                    Text(store.quote?.formattedPrice ?? "--")
                        .font(.system(size: isCompact ? 19 : 22, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .contentTransition(.numericText())
                    Text(store.quote.map { "\($0.isPositive ? "+" : "−")\(String(format: "%.2f", abs($0.changePercent)))%" } ?? (store.isRefreshing ? "Loading quote" : "Open for details"))
                        .font(.system(size: 9, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(tint)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                StockSparkline(points: store.quote?.points ?? [], tint: tint)
                    .frame(width: isCompact ? 48 : 72, height: 35)
            }
            .padding(.horizontal, 11)
            .frame(width: isCompact ? 158 : 198, height: 79)
            .background(Color.black.opacity(0.68), in: RoundedRectangle(cornerRadius: 23, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 23, style: .continuous).stroke(.white.opacity(0.11), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingPopover, arrowEdge: .bottom) {
            let height = StockPopover.preferredHeight(forVisibleHeight: NSScreen.main?.visibleFrame.height ?? 720)
            StockPopover(store: store, maxHeight: height)
        }
        .accessibilityLabel(stockAccessibilityLabel)
        .help("Open stock details for \(store.symbol)")
        .task { await store.refresh() }
    }

    private var stockAccessibilityLabel: String {
        guard let quote = store.quote else { return "Stock price for \(store.symbol), loading" }
        return "\(quote.symbol), \(quote.formattedPrice), \(quote.formattedChange). Open stock chart"
    }
}

struct StockPopover: View {
    @ObservedObject var store: StockStore
    @State private var hoveredIndex: Int?
    var maxHeight: CGFloat = 400

    static func preferredHeight(forVisibleHeight visibleHeight: CGFloat) -> CGFloat {
        min(360, max(280, visibleHeight * 0.46))
    }

    private var tint: Color { store.quote?.isPositive == false ? .red : .green }
    private var highlighted: StockChartPoint? {
        guard let hoveredIndex, store.chartPoints.indices.contains(hoveredIndex) else { return nil }
        return store.chartPoints[hoveredIndex]
    }
    var body: some View {
        ScrollView(.vertical) {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label("Stocks", systemImage: "chart.xyaxis.line").font(.system(size: 15, weight: .semibold))
                Spacer()
                Text("\(store.watchlist.count)/12").font(.caption).foregroundStyle(.secondary)
                Button { Task { await store.refresh(); await store.refreshWatchlist() } } label: {
                    Image(systemName: "arrow.clockwise")
                }.buttonStyle(.borderless).controlSize(.small).disabled(store.isRefreshing).help("Refresh watchlist")
            }
            HStack(spacing: 7) {
                TextField("Ticker or company", text: $store.symbolDraft)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .onSubmit(store.applySymbol)
                    .frame(minWidth: 70)
                Button { Task { await store.searchCompanies() } } label: {
                    if store.isSearching { ProgressView().controlSize(.small) }
                    else { Image(systemName: "magnifyingglass") }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Find companies")
                .help("Find companies by name or ticker")
                .disabled(store.isSearching || store.symbolDraft.trimmingCharacters(in: .whitespacesAndNewlines).count < 2)
                Button("Add / Show", action: store.applySymbol)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            if !store.searchResults.isEmpty {
                ScrollView(.vertical) {
                    VStack(spacing: 2) {
                        ForEach(store.searchResults) { result in
                            Button { store.selectSearchResult(result) } label: {
                                HStack(spacing: 8) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(result.name).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                                        Text("\(result.symbol) · \(result.exchDisp ?? result.quoteType ?? "Market")").font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Spacer(); Image(systemName: store.watchlist.contains(result.symbol) ? "checkmark" : "plus").foregroundStyle(.secondary)
                                }.padding(.vertical, 4).contentShape(Rectangle())
                            }.buttonStyle(.plain).disabled(store.watchlist.contains(result.symbol) || store.watchlist.count >= 12)
                        }
                    }
                }.frame(maxHeight: 96).padding(7).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
            }
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(store.watchlist, id: \.self) { symbol in
                        Button { store.select(symbol) } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(symbol).font(.system(size: 11, weight: .semibold))
                                Text(store.quotes[symbol].map { String(format: "%+.2f%%", $0.changePercent) } ?? "—")
                                    .font(.system(size: 10).monospacedDigit())
                                    .foregroundStyle(store.quotes[symbol]?.isPositive == false ? .red : .green)
                            }.padding(9).background(store.symbol == symbol ? .white.opacity(0.14) : .white.opacity(0.04), in: RoundedRectangle(cornerRadius: 9))
                        }.buttonStyle(.plain).help("Show \(symbol); right-click to remove")
                            .contextMenu { Button("Remove from watchlist") { store.remove(symbol) }.disabled(store.watchlist.count == 1) }
                    }
                }
            }.scrollIndicators(.hidden)
            if let quote = store.quote {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(quote.formattedPrice).font(.system(size: 24, weight: .semibold, design: .rounded).monospacedDigit()).lineLimit(1).minimumScaleFactor(0.75)
                        Spacer(minLength: 0)
                        if quote.currency != "USD" {
                            Text(quote.currency).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Text(quote.formattedChange + " today").font(.system(size: 10, weight: .medium)).foregroundStyle(tint)
                }
            } else {
                HStack { if store.isRefreshing { ProgressView().controlSize(.small) }; Text("\(store.symbol) · No quote yet").foregroundStyle(.secondary) }.padding(.vertical, 12)
            }
            Picker("Chart range", selection: Binding(get: { store.range }, set: store.selectRange)) {
                ForEach(StockRange.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).controlSize(.small)
            VStack(spacing: 5) {
                HStack {
                    if let point = highlighted {
                        Text(point.price.formatted(.number.precision(.fractionLength(2)))).fontWeight(.semibold)
                        Spacer()
                        Text(Date(timeIntervalSince1970: Double(point.timestamp)).formatted(date: .abbreviated, time: .shortened))
                    } else {
                        Text(store.range.rawValue + " price history")
                        Spacer()
                        Text("Hover to inspect")
                    }
                }.font(.system(size: 10)).foregroundStyle(.secondary)
                GeometryReader { geometry in
                    StockSparkline(points: store.chartPoints, tint: tint)
                        .overlay(alignment: .leading) {
                            if let hoveredIndex, store.chartPoints.count > 1 {
                                Rectangle().fill(.white.opacity(0.35)).frame(width: 1)
                                    .offset(x: geometry.size.width * CGFloat(hoveredIndex) / CGFloat(store.chartPoints.count - 1))
                            }
                        }
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                let fraction = min(1, max(0, location.x / max(geometry.size.width, 1)))
                                hoveredIndex = Int((fraction * Double(max(0, store.chartPoints.count - 1))).rounded())
                            case .ended: hoveredIndex = nil
                            }
                        }
                }.frame(height: 44)
                    .overlay { if store.isChartRefreshing { ProgressView().controlSize(.small) } }
                HStack {
                    if let low = store.chartPoints.map(\.price).min(), let high = store.chartPoints.map(\.price).max() {
                        Text("Low \(low, specifier: "%.2f")"); Spacer(); Text("High \(high, specifier: "%.2f")")
                    }
                }.font(.caption2).foregroundStyle(.secondary)
            }.padding(8).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
            if let error = store.errorMessage ?? store.chartError { Text(error).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Text(store.quote?.updateDescription ?? "Waiting for data")
                Spacer()
                if store.watchlist.count > 1 { Button("Next ticker", action: store.nextSymbol).buttonStyle(.borderless) }
            }.font(.caption2).foregroundStyle(.secondary)
            Text("Yahoo Finance · Quotes may be delayed · cached offline")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .padding(11)
        .frame(width: 320, alignment: .topLeading)
        }
        .scrollIndicators(.hidden)
        .frame(width: 320, height: maxHeight)
        .background(Color(red: 0.075, green: 0.085, blue: 0.10), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.white.opacity(0.08), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .task { await store.refreshWatchlist() }
            .onChange(of: store.range) { _, _ in hoveredIndex = nil }
            .onChange(of: store.symbol) { _, _ in hoveredIndex = nil }
    }
}

struct StockSparkline: View {
    let points: [StockChartPoint]
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            let coords = coordinates(in: proxy.size)
            if coords.count > 1, let first = coords.first, let last = coords.last {
                ZStack {
                    Path { path in
                        path.move(to: first)
                        for point in coords.dropFirst() { path.addLine(to: point) }
                        path.addLine(to: CGPoint(x: last.x, y: proxy.size.height))
                        path.addLine(to: CGPoint(x: first.x, y: proxy.size.height))
                        path.closeSubpath()
                    }
                    .fill(LinearGradient(colors: [tint.opacity(0.22), tint.opacity(0.01)], startPoint: .top, endPoint: .bottom))

                    Path { path in
                        path.move(to: first)
                        for point in coords.dropFirst() { path.addLine(to: point) }
                    }
                    .stroke(tint, style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))
                }
            } else {
                Image(systemName: "chart.xyaxis.line")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(tint.opacity(0.55))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .accessibilityHidden(true)
    }

    private func coordinates(in size: CGSize) -> [CGPoint] {
        guard points.count > 1, size.width > 2, size.height > 2 else { return [] }
        let values = points.map(\.price)
        guard let minimum = values.min(), let maximum = values.max() else { return [] }
        let padding = max((maximum - minimum) * 0.12, max(abs(maximum) * 0.002, 0.01))
        let lower = minimum - padding
        let range = max(maximum - minimum + padding * 2, 0.01)
        let usableHeight = size.height - 4
        let denominator = CGFloat(max(points.count - 1, 1))

        return points.enumerated().map { index, point in
            let x = 1 + (size.width - 2) * CGFloat(index) / denominator
            let normalized = (point.price - lower) / range
            let y = 2 + usableHeight * (1 - normalized)
            return CGPoint(x: x, y: y)
        }
    }
}
