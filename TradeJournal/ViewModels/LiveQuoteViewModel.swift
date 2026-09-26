import Foundation
import Observation

/// Viewmodel achter de live-koerskaart op het dashboard.
///
/// - Bepaalt het symbool uit de meest recente trade (of de vaste keuze in
///   `LiveQuoteSettings`).
/// - Ververst periodiek zolang `start()` actief is: elke 30 s met open markt,
///   elke 5 min met gesloten markt, na een fout na 60 s. De view roept
///   `stop()` aan zodra de app naar de achtergrond gaat of het dashboard
///   verdwijnt, zodat er dan niet gepold wordt.
@MainActor
@Observable
public final class LiveQuoteViewModel {

    public enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    public static let openInterval: TimeInterval = 30
    public static let closedInterval: TimeInterval = 300
    public static let errorInterval: TimeInterval = 60

    public private(set) var phase: Phase = .idle
    /// Laatst geladen koers; blijft zichtbaar als een verversing mislukt.
    public private(set) var quote: LiveQuote?
    public private(set) var symbol: QuoteSymbol?

    public let provider: any QuoteProviding
    public let settings: LiveQuoteSettings

    @ObservationIgnored private var pollTask: Task<Void, Never>?

    public init(provider: any QuoteProviding = YahooQuoteProvider(), settings: LiveQuoteSettings = LiveQuoteSettings()) {
        self.provider = provider
        self.settings = settings
    }

    public var isEnabled: Bool { settings.isEnabled }
    public var isPolling: Bool { pollTask != nil }
    public var sourceName: String { provider.sourceName }

    // MARK: - Symbool

    /// Symbool voor de kaart: de vaste keuze, anders het instrument van de
    /// trade met de meest recente entry/exit.
    public static func symbol(for trades: [Trade], override: String?) -> QuoteSymbol? {
        if let override, let resolved = QuoteSymbolResolver.resolve(override) { return resolved }
        let latest = trades.max { lhs, rhs in
            (lhs.exitDate ?? lhs.entryDate) < (rhs.exitDate ?? rhs.entryDate)
        }
        guard let latest else { return nil }
        return QuoteSymbolResolver.resolve(latest.symbol, category: latest.instrument?.category)
    }

    /// Werkt het symbool bij (bijv. na een nieuwe trade). Een ander symbool
    /// wist de oude koers en haalt direct de nieuwe op als er gepold wordt.
    public func update(trades: [Trade]) {
        let newSymbol = Self.symbol(for: trades, override: settings.symbolOverride)
        guard newSymbol != symbol else { return }
        symbol = newSymbol
        quote = nil
        phase = .idle
        if isPolling {
            stop()
            start()
        }
    }

    // MARK: - Verversen

    public static func interval(after phase: Phase, quote: LiveQuote?) -> TimeInterval {
        if case .failed = phase { return errorInterval }
        return (quote?.isMarketOpen ?? false) ? openInterval : closedInterval
    }

    /// Begint met pollen (direct een eerste verversing). Doet niets als de
    /// kaart uit staat, er geen symbool is of er al gepold wordt.
    public func start() {
        guard pollTask == nil, isEnabled, symbol != nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                let seconds = Self.interval(after: self.phase, quote: self.quote)
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            }
        }
    }

    public func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    public func refresh() async {
        guard let symbol else { return }
        if quote == nil { phase = .loading }
        do {
            let fresh = try await provider.quote(for: symbol)
            guard !Task.isCancelled, symbol == self.symbol else { return }
            quote = fresh
            phase = .loaded
        } catch {
            guard !Task.isCancelled, symbol == self.symbol else { return }
            phase = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }
}
