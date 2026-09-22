import Foundation
import Compression

/// Minimale, dependency-vrije ZIP-ondersteuning voor backups.
///
/// iOS heeft geen publieke API om zip-bestanden te lezen, dus schrijven én
/// lezen gebeurt hier met de hand volgens de PKWARE-specificatie (APPNOTE):
/// - methodes 0 (stored) en 8 (deflate, via het `Compression`-framework,
///   dat met `COMPRESSION_ZLIB` raw DEFLATE levert zoals zip verwacht);
/// - geen ZIP64: maximaal 65.535 bestanden en 4 GB per archief, ruim genoeg
///   voor een journal-backup;
/// - bestandsnamen in UTF-8 (general purpose flag bit 11).
///
/// Bestanden uit het archief worden alleen op naam in het geheugen gelezen,
/// nooit naar schijf uitgepakt — er is dus geen risico op "zip slip".
public enum ZipArchive {

    public enum ZipError: Error, Equatable, LocalizedError {
        case notAZipFile
        case corrupt(String)
        case unsupportedCompression(UInt16)
        case entryNotFound(String)
        case checksumMismatch(String)
        case tooLarge

        public var errorDescription: String? {
            switch self {
            case .notAZipFile: return "Het bestand is geen geldig zip-archief."
            case .corrupt(let detail): return "Het zip-archief is beschadigd (\(detail))."
            case .unsupportedCompression(let method): return "Niet-ondersteunde compressiemethode (\(method))."
            case .entryNotFound(let path): return "Bestand \"\(path)\" ontbreekt in het archief."
            case .checksumMismatch(let path): return "Controlesom klopt niet voor \"\(path)\"."
            case .tooLarge: return "De backup is te groot voor het zip-formaat (max. 4 GB / 65.535 bestanden)."
            }
        }
    }

    static let localHeaderSignature: UInt32 = 0x0403_4B50
    static let centralHeaderSignature: UInt32 = 0x0201_4B50
    static let endOfCentralDirectorySignature: UInt32 = 0x0605_4B50
    static let utf8Flag: UInt16 = 1 << 11

    // MARK: - CRC-32

    private static let crcTable: [UInt32] = (0..<256).map { index -> UInt32 in
        var crc = UInt32(index)
        for _ in 0..<8 {
            crc = (crc & 1) != 0 ? (0xEDB8_8320 ^ (crc >> 1)) : (crc >> 1)
        }
        return crc
    }

    /// CRC-32 (IEEE 802.3), zoals zip hem gebruikt.
    public static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            for byte in buffer {
                crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
            }
        }
        return crc ^ 0xFFFF_FFFF
    }

    // MARK: - Deflate

    /// Raw DEFLATE. Geeft `nil` terug als comprimeren niets oplevert.
    static func deflate(_ data: Data) -> Data? {
        guard data.count > 64 else { return nil }
        let capacity = data.count
        var output = Data(count: capacity)
        let written = output.withUnsafeMutableBytes { (dst: UnsafeMutableRawBufferPointer) -> Int in
            data.withUnsafeBytes { (src: UnsafeRawBufferPointer) -> Int in
                guard let dstBase = dst.bindMemory(to: UInt8.self).baseAddress,
                      let srcBase = src.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_encode_buffer(dstBase, capacity, srcBase, data.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard written > 0, written < data.count else { return nil }
        return Data(output.prefix(written))
    }

    static func inflate(_ data: Data, expectedSize: Int) -> Data? {
        guard expectedSize > 0 else { return Data() }
        guard !data.isEmpty else { return nil }
        var output = Data(count: expectedSize)
        let written = output.withUnsafeMutableBytes { (dst: UnsafeMutableRawBufferPointer) -> Int in
            data.withUnsafeBytes { (src: UnsafeRawBufferPointer) -> Int in
                guard let dstBase = dst.bindMemory(to: UInt8.self).baseAddress,
                      let srcBase = src.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(dstBase, expectedSize, srcBase, data.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard written == expectedSize else { return nil }
        return output
    }

    // MARK: - DOS-tijd

    static func dosDateTime(_ date: Date) -> (time: UInt16, date: UInt16) {
        let components = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let year: Int = min(max((components.year ?? 1980) - 1980, 0), 127)
        let month: Int = components.month ?? 1
        let dayOfMonth: Int = components.day ?? 1
        let hour: Int = components.hour ?? 0
        let minute: Int = components.minute ?? 0
        let second: Int = components.second ?? 0

        let timeBits: Int = (hour << 11) | (minute << 5) | (second / 2)
        let dateBits: Int = (year << 9) | (month << 5) | dayOfMonth
        return (UInt16(timeBits), UInt16(dateBits))
    }
}

// MARK: - Writer

/// Schrijft een zip-archief streaming naar schijf, zodat grote backups met
/// veel screenshots niet in één keer in het geheugen hoeven te staan.
public final class ZipWriter {

    private struct CentralEntry {
        let nameBytes: Data
        let method: UInt16
        let time: UInt16
        let date: UInt16
        let crc: UInt32
        let compressedSize: UInt32
        let uncompressedSize: UInt32
        let offset: UInt32
    }

    private let handle: FileHandle
    private var offset: UInt64 = 0
    private var entries: [CentralEntry] = []
    private let modificationDate: Date
    private var isFinished = false

    /// Maakt (of overschrijft) het archief op `url`.
    public init(url: URL, modificationDate: Date = Date()) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        self.handle = try FileHandle(forWritingTo: url)
        self.modificationDate = modificationDate
    }

    deinit {
        if !isFinished { try? handle.close() }
    }

    /// Voegt een bestand toe. Met `compress: true` wordt deflate geprobeerd
    /// (alleen gebruikt als het kleiner wordt); JPEG/PNG kun je beter
    /// ongecomprimeerd opslaan omdat die al gecomprimeerd zijn.
    public func addFile(path: String, data: Data, compress: Bool = true) throws {
        let compressed = compress ? ZipArchive.deflate(data) : nil
        let payload = compressed ?? data
        let method: UInt16 = compressed == nil ? 0 : 8
        let nameBytes = Data(path.utf8)
        let crc = ZipArchive.crc32(data)
        let (time, date) = ZipArchive.dosDateTime(modificationDate)

        guard offset <= UInt64(UInt32.max),
              data.count <= Int(UInt32.max),
              entries.count < Int(UInt16.max) else {
            throw ZipArchive.ZipError.tooLarge
        }

        var header = Data()
        header.appendLE(ZipArchive.localHeaderSignature)
        header.appendLE(UInt16(20))                 // version needed
        header.appendLE(ZipArchive.utf8Flag)        // flags
        header.appendLE(method)
        header.appendLE(time)
        header.appendLE(date)
        header.appendLE(crc)
        header.appendLE(UInt32(payload.count))
        header.appendLE(UInt32(data.count))
        header.appendLE(UInt16(nameBytes.count))
        header.appendLE(UInt16(0))                  // extra field length
        header.append(nameBytes)

        entries.append(CentralEntry(
            nameBytes: nameBytes,
            method: method,
            time: time,
            date: date,
            crc: crc,
            compressedSize: UInt32(payload.count),
            uncompressedSize: UInt32(data.count),
            offset: UInt32(offset)
        ))

        try write(header)
        try write(payload)
    }

    /// Schrijft de central directory en sluit het bestand.
    public func finish() throws {
        guard !isFinished else { return }
        let centralStart = offset
        guard centralStart <= UInt64(UInt32.max) else { throw ZipArchive.ZipError.tooLarge }

        var central = Data()
        for entry in entries {
            central.appendLE(ZipArchive.centralHeaderSignature)
            central.appendLE(UInt16(20))            // version made by
            central.appendLE(UInt16(20))            // version needed
            central.appendLE(ZipArchive.utf8Flag)
            central.appendLE(entry.method)
            central.appendLE(entry.time)
            central.appendLE(entry.date)
            central.appendLE(entry.crc)
            central.appendLE(entry.compressedSize)
            central.appendLE(entry.uncompressedSize)
            central.appendLE(UInt16(entry.nameBytes.count))
            central.appendLE(UInt16(0))             // extra
            central.appendLE(UInt16(0))             // comment
            central.appendLE(UInt16(0))             // disk number start
            central.appendLE(UInt16(0))             // internal attributes
            central.appendLE(UInt32(0))             // external attributes
            central.appendLE(entry.offset)
            central.append(entry.nameBytes)
        }
        try write(central)

        guard offset <= UInt64(UInt32.max) else { throw ZipArchive.ZipError.tooLarge }
        var end = Data()
        end.appendLE(ZipArchive.endOfCentralDirectorySignature)
        end.appendLE(UInt16(0))                     // this disk
        end.appendLE(UInt16(0))                     // disk with central directory
        end.appendLE(UInt16(entries.count))
        end.appendLE(UInt16(entries.count))
        end.appendLE(UInt32(central.count))
        end.appendLE(UInt32(centralStart))
        end.appendLE(UInt16(0))                     // comment length
        try write(end)

        try handle.close()
        isFinished = true
    }

    private func write(_ data: Data) throws {
        try handle.write(contentsOf: data)
        offset += UInt64(data.count)
    }
}

// MARK: - Reader

/// Leest bestanden uit een zip-archief (stored of deflate).
public struct ZipReader {

    public struct Entry: Equatable, Sendable {
        public let path: String
        let method: UInt16
        let crc: UInt32
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int
    }

    private let data: Data
    public let entries: [Entry]

    /// Opent een archief van schijf. Het bestand wordt gememory-mapt, zodat
    /// grote backups niet volledig in het geheugen geladen worden.
    public init(url: URL) throws {
        try self.init(data: Data(contentsOf: url, options: .alwaysMapped))
    }

    public init(data: Data) throws {
        self.data = data
        self.entries = try Self.readCentralDirectory(data)
    }

    public var paths: [String] { entries.map(\.path) }

    public func contains(_ path: String) -> Bool {
        entries.contains { $0.path == path }
    }

    /// Uitgepakte inhoud van `path`, met CRC-controle.
    public func data(for path: String) throws -> Data {
        guard let entry = entries.first(where: { $0.path == path }) else {
            throw ZipArchive.ZipError.entryNotFound(path)
        }
        return try extract(entry)
    }

    public func extract(_ entry: Entry) throws -> Data {
        let local = entry.localHeaderOffset
        guard try data.readLE32(at: local) == ZipArchive.localHeaderSignature else {
            throw ZipArchive.ZipError.corrupt("local header")
        }
        let nameLength = Int(try data.readLE16(at: local + 26))
        let extraLength = Int(try data.readLE16(at: local + 28))
        let start = local + 30 + nameLength + extraLength
        guard start >= 0, start + entry.compressedSize <= data.count else {
            throw ZipArchive.ZipError.corrupt("data buiten archief")
        }
        let base = data.startIndex
        let raw = data.subdata(in: (base + start)..<(base + start + entry.compressedSize))

        let output: Data
        switch entry.method {
        case 0:
            output = raw
        case 8:
            guard let inflated = ZipArchive.inflate(raw, expectedSize: entry.uncompressedSize) else {
                throw ZipArchive.ZipError.corrupt("deflate")
            }
            output = inflated
        default:
            throw ZipArchive.ZipError.unsupportedCompression(entry.method)
        }

        guard ZipArchive.crc32(output) == entry.crc else {
            throw ZipArchive.ZipError.checksumMismatch(entry.path)
        }
        return output
    }

    private static func readCentralDirectory(_ data: Data) throws -> [Entry] {
        guard data.count >= 22 else { throw ZipArchive.ZipError.notAZipFile }

        // End of central directory staat aan het eind, eventueel gevolgd
        // door een commentaar van max. 65.535 bytes.
        var eocd: Int?
        var position = data.count - 22
        let lowerBound = max(0, data.count - 22 - 65_535)
        while position >= lowerBound {
            if try data.readLE32(at: position) == ZipArchive.endOfCentralDirectorySignature {
                eocd = position
                break
            }
            position -= 1
        }
        guard let end = eocd else { throw ZipArchive.ZipError.notAZipFile }

        let count = Int(try data.readLE16(at: end + 10))
        let centralSize = Int(try data.readLE32(at: end + 12))
        let centralOffset = Int(try data.readLE32(at: end + 16))
        guard centralOffset + centralSize <= data.count else {
            throw ZipArchive.ZipError.corrupt("central directory")
        }

        var entries: [Entry] = []
        entries.reserveCapacity(count)
        var cursor = centralOffset
        for _ in 0..<count {
            guard try data.readLE32(at: cursor) == ZipArchive.centralHeaderSignature else {
                throw ZipArchive.ZipError.corrupt("central header")
            }
            let flags = try data.readLE16(at: cursor + 8)
            let method = try data.readLE16(at: cursor + 10)
            let crc = try data.readLE32(at: cursor + 16)
            let compressedSize = Int(try data.readLE32(at: cursor + 20))
            let uncompressedSize = Int(try data.readLE32(at: cursor + 24))
            let nameLength = Int(try data.readLE16(at: cursor + 28))
            let extraLength = Int(try data.readLE16(at: cursor + 30))
            let commentLength = Int(try data.readLE16(at: cursor + 32))
            let localOffset = Int(try data.readLE32(at: cursor + 42))

            let nameStart = cursor + 46
            guard nameStart + nameLength <= data.count else { throw ZipArchive.ZipError.corrupt("naam") }
            let base = data.startIndex
            let nameData = data.subdata(in: (base + nameStart)..<(base + nameStart + nameLength))
            let encoding: String.Encoding = (flags & ZipArchive.utf8Flag) != 0 ? .utf8 : .isoLatin1
            let path = String(data: nameData, encoding: encoding) ?? String(decoding: nameData, as: UTF8.self)

            entries.append(Entry(
                path: path,
                method: method,
                crc: crc,
                compressedSize: compressedSize,
                uncompressedSize: uncompressedSize,
                localHeaderOffset: localOffset
            ))
            cursor = nameStart + nameLength + extraLength + commentLength
        }
        return entries
    }
}

// MARK: - Little-endian helpers

extension Data {
    mutating func appendLE(_ value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
    }

    mutating func appendLE(_ value: UInt32) {
        for shift in stride(from: 0, to: 32, by: 8) {
            append(UInt8((value >> UInt32(shift)) & 0xFF))
        }
    }

    func readLE16(at offset: Int) throws -> UInt16 {
        guard offset >= 0, offset + 2 <= count else { throw ZipArchive.ZipError.corrupt("buiten bereik") }
        let base = startIndex + offset
        return UInt16(self[base]) | (UInt16(self[base + 1]) << 8)
    }

    func readLE32(at offset: Int) throws -> UInt32 {
        guard offset >= 0, offset + 4 <= count else { throw ZipArchive.ZipError.corrupt("buiten bereik") }
        let base = startIndex + offset
        return UInt32(self[base])
            | (UInt32(self[base + 1]) << 8)
            | (UInt32(self[base + 2]) << 16)
            | (UInt32(self[base + 3]) << 24)
    }
}
