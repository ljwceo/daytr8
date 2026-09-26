import Foundation

/// Een symbool zoals de koersbron het kent, afgeleid van het symbool van een trade.
public struct QuoteSymbol: Equatable, Hashable, Sendable {

    public enum Kind: String, Sendable {
        case future
        case index
        case stock
        case forex
        case crypto
    }

    /// Wat de gebruiker ziet (bijv. "MNQ").
    public let display: String
    /// Wat de koersbron verwacht (bijv. "MNQ=F" voor het doorlopende contract).
    public let providerSymbol: String
    public let kind: Kind

    public init(display: String, providerSymbol: String, kind: Kind) {
        self.display = display
        self.providerSymbol = providerSymbol
        self.kind = kind
    }
}

/// Eén punt van de intraday-sparkline.
public struct QuotePoint: Equatable, Sendable, Identifiable {
    public let date: Date
    public let price: Double
    public var id: Date { date }

    public init(date: Date, price: Double) {
        self.date = date
        self.price = price
    }
}

/// Koers van één instrument zoals de live-koerskaart hem toont.
public struct LiveQuote: Equatable, Sendable {
    public let symbol: QuoteSymbol
    public let price: Double
    /// Slot van de vorige handelsdag; basis voor "verandering vandaag".
    public let previousClose: Double?
    public let currency: String?
    /// Tijdstip van de laatste koers volgens de bron.
    public let lastUpdate: Date
    /// Intraday-koersen (oud → nieuw).
    public let points: [QuotePoint]
    public let isMarketOpen: Bool
    /// Vertraging van de data in minuten (0 = realtime volgens de bron).
    public let delayMinutes: Int

    public init(
        symbol: QuoteSymbol,
        price: Double,
        previousClose: Double?,
        currency: String?,
        lastUpdate: Date,
        points: [QuotePoint],
        isMarketOpen: Bool,
        delayMinutes: Int
    ) {
        self.symbol = symbol
        self.price = price
        self.previousClose = previousClose
        self.currency = currency
        self.lastUpdate = lastUpdate
        self.points = points
        self.isMarketOpen = isMarketOpen
        self.delayMinutes = delayMinutes
    }

    /// Verandering t.o.v. het vorige slot, `nil` als dat onbekend is.
    public var change: Double? {
        previousClose.map { price - $0 }
    }

    /// Verandering als fractie (0,012 = +1,2%).
    public var changeFraction: Double? {
        guard let previousClose, previousClose != 0 else { return nil }
        return (price - previousClose) / previousClose
    }

    public var isDelayed: Bool { delayMinutes > 0 }
}
