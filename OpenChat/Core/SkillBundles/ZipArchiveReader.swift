import Foundation
import zlib

enum ZipArchiveError: LocalizedError, Sendable {
    case invalidArchive
    case zip64Unsupported
    case encryptedEntry(String)
    case unsupportedCompressionMethod(Int, String)
    case unsafePath(String)
    case duplicateFilePath(String)
    case fileTooLarge(String)
    case expandedArchiveTooLarge
    case corruptedEntry(String)

    var errorDescription: String? {
        switch self {
        case .invalidArchive:
            String(localized: "ZIP archive is invalid.")
        case .zip64Unsupported:
            String(localized: "ZIP64 archives are not supported.")
        case let .encryptedEntry(path):
            String(localized: "ZIP entry is encrypted and cannot be imported: \(path)")
        case let .unsupportedCompressionMethod(method, path):
            String(localized: "ZIP entry uses unsupported compression method \(method): \(path)")
        case let .unsafePath(path):
            String(localized: "ZIP entry path is unsafe: \(path)")
        case let .duplicateFilePath(path):
            String(localized: "ZIP archive contains duplicate file paths: \(path)")
        case let .fileTooLarge(path):
            String(localized: "ZIP entry is too large to import: \(path)")
        case .expandedArchiveTooLarge:
            String(localized: "ZIP archive expands to too much data.")
        case let .corruptedEntry(path):
            String(localized: "ZIP entry is corrupted: \(path)")
        }
    }
}

struct ZipArchiveEntry: Sendable, Equatable {
    var relativePath: String
    var data: Data
}

struct ZipArchiveReader: Sendable {
    var maxEntryCount = 2_048
    var maxEntryUncompressedBytes = 20_000_000
    var maxTotalUncompressedBytes = 100_000_000

    func read(_ data: Data) throws -> [ZipArchiveEntry] {
        let centralDirectory = try centralDirectory(in: data)
        var offset = centralDirectory.offset
        var entries: [ZipArchiveEntry] = []
        var seenPaths = Set<String>()
        var expandedBytes = 0

        guard centralDirectory.entryCount <= maxEntryCount else {
            throw ZipArchiveError.expandedArchiveTooLarge
        }

        for _ in 0..<centralDirectory.entryCount {
            guard try data.uint32(at: offset) == 0x0201_4B50 else {
                throw ZipArchiveError.invalidArchive
            }

            let flags = try data.uint16(at: offset + 8)
            let compressionMethod = Int(try data.uint16(at: offset + 10))
            let compressedSize = try data.checkedInt32(at: offset + 20)
            let uncompressedSize = try data.checkedInt32(at: offset + 24)
            let fileNameLength = Int(try data.uint16(at: offset + 28))
            let extraFieldLength = Int(try data.uint16(at: offset + 30))
            let fileCommentLength = Int(try data.uint16(at: offset + 32))
            let localHeaderOffset = try data.checkedInt32(at: offset + 42)
            let nameData = try data.subdataChecked(
                offset: offset + 46,
                length: fileNameLength
            )
            let rawPath = String(data: nameData, encoding: .utf8)
                ?? String(data: nameData, encoding: .isoLatin1)
                ?? ""
            let nextCentralOffset = offset + 46 + fileNameLength + extraFieldLength + fileCommentLength
            offset = nextCentralOffset

            guard !rawPath.isEmpty else {
                throw ZipArchiveError.invalidArchive
            }
            if Self.shouldSkip(rawPath) || rawPath.hasSuffix("/") {
                continue
            }

            let relativePath = try Self.normalizedRelativePath(rawPath)
            guard seenPaths.insert(relativePath).inserted else {
                throw ZipArchiveError.duplicateFilePath(relativePath)
            }
            guard flags & 0x0001 == 0 else {
                throw ZipArchiveError.encryptedEntry(relativePath)
            }
            guard uncompressedSize <= maxEntryUncompressedBytes else {
                throw ZipArchiveError.fileTooLarge(relativePath)
            }
            expandedBytes += uncompressedSize
            guard expandedBytes <= maxTotalUncompressedBytes else {
                throw ZipArchiveError.expandedArchiveTooLarge
            }

            let payload = try localPayload(
                in: data,
                localHeaderOffset: localHeaderOffset,
                compressedSize: compressedSize,
                relativePath: relativePath
            )
            let entryData: Data
            switch compressionMethod {
            case 0:
                guard payload.count == uncompressedSize else {
                    throw ZipArchiveError.corruptedEntry(relativePath)
                }
                entryData = payload
            case 8:
                entryData = try Self.inflateRawDeflate(
                    payload,
                    expectedSize: uncompressedSize,
                    relativePath: relativePath
                )
            default:
                throw ZipArchiveError.unsupportedCompressionMethod(compressionMethod, relativePath)
            }
            entries.append(ZipArchiveEntry(relativePath: relativePath, data: entryData))
        }

        return entries.sorted { $0.relativePath < $1.relativePath }
    }

    private func centralDirectory(in data: Data) throws -> ZipCentralDirectory {
        guard data.count >= 22 else {
            throw ZipArchiveError.invalidArchive
        }

        let minimumEOCDSize = 22
        let searchStart = max(0, data.count - minimumEOCDSize - 65_535)
        var offset = data.count - minimumEOCDSize
        while offset >= searchStart {
            if (try? data.uint32(at: offset)) == 0x0605_4B50 {
                let diskNumber = try data.uint16(at: offset + 4)
                let centralDirectoryDisk = try data.uint16(at: offset + 6)
                let entryCountOnDisk = try data.uint16(at: offset + 8)
                let entryCount = try data.uint16(at: offset + 10)
                let centralDirectorySize = try data.uint32(at: offset + 12)
                let centralDirectoryOffset = try data.uint32(at: offset + 16)
                guard diskNumber == 0,
                      centralDirectoryDisk == 0,
                      entryCountOnDisk == entryCount
                else {
                    throw ZipArchiveError.invalidArchive
                }
                guard entryCount != UInt16.max,
                      centralDirectorySize != UInt32.max,
                      centralDirectoryOffset != UInt32.max
                else {
                    throw ZipArchiveError.zip64Unsupported
                }
                let directoryOffset = Int(centralDirectoryOffset)
                let directorySize = Int(centralDirectorySize)
                guard directoryOffset >= 0,
                      directorySize >= 0,
                      directoryOffset + directorySize <= data.count
                else {
                    throw ZipArchiveError.invalidArchive
                }
                return ZipCentralDirectory(
                    offset: directoryOffset,
                    entryCount: Int(entryCount)
                )
            }
            if offset == 0 { break }
            offset -= 1
        }

        throw ZipArchiveError.invalidArchive
    }

    private func localPayload(
        in data: Data,
        localHeaderOffset: Int,
        compressedSize: Int,
        relativePath: String
    ) throws -> Data {
        guard try data.uint32(at: localHeaderOffset) == 0x0403_4B50 else {
            throw ZipArchiveError.corruptedEntry(relativePath)
        }
        let fileNameLength = Int(try data.uint16(at: localHeaderOffset + 26))
        let extraFieldLength = Int(try data.uint16(at: localHeaderOffset + 28))
        let payloadOffset = localHeaderOffset + 30 + fileNameLength + extraFieldLength
        return try data.subdataChecked(offset: payloadOffset, length: compressedSize)
    }

    private static func inflateRawDeflate(
        _ input: Data,
        expectedSize: Int,
        relativePath: String
    ) throws -> Data {
        guard expectedSize > 0 else { return Data() }

        var stream = z_stream()
        let initStatus = inflateInit2_(&stream, -15, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard initStatus == Z_OK else {
            throw ZipArchiveError.corruptedEntry(relativePath)
        }
        defer { inflateEnd(&stream) }

        var output = Data(count: expectedSize)
        let status: Int32 = input.withUnsafeBytes { inputBuffer in
            output.withUnsafeMutableBytes { outputBuffer in
                stream.next_in = UnsafeMutablePointer<Bytef>(
                    mutating: inputBuffer.bindMemory(to: Bytef.self).baseAddress
                )
                stream.avail_in = uInt(inputBuffer.count)
                stream.next_out = outputBuffer.bindMemory(to: Bytef.self).baseAddress
                stream.avail_out = uInt(outputBuffer.count)
                return inflate(&stream, Z_FINISH)
            }
        }

        guard status == Z_STREAM_END, Int(stream.total_out) == expectedSize else {
            throw ZipArchiveError.corruptedEntry(relativePath)
        }
        output.count = Int(stream.total_out)
        return output
    }

    private static func normalizedRelativePath(_ rawPath: String) throws -> String {
        let normalized = rawPath.replacingOccurrences(of: "\\", with: "/")
        let components = normalized
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        guard !normalized.hasPrefix("/"),
              !components.isEmpty,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("\0") }) else {
            throw ZipArchiveError.unsafePath(rawPath)
        }
        return components.joined(separator: "/")
    }

    private static func shouldSkip(_ rawPath: String) -> Bool {
        let normalized = rawPath.replacingOccurrences(of: "\\", with: "/")
        if normalized.hasPrefix("__MACOSX/") {
            return true
        }
        return normalized.split(separator: "/").last == ".DS_Store"
    }
}

private struct ZipCentralDirectory {
    var offset: Int
    var entryCount: Int
}

private extension Data {
    func uint16(at offset: Int) throws -> UInt16 {
        guard offset >= 0, offset + 2 <= count else {
            throw ZipArchiveError.invalidArchive
        }
        return UInt16(self[offset])
            | (UInt16(self[offset + 1]) << 8)
    }

    func uint32(at offset: Int) throws -> UInt32 {
        guard offset >= 0, offset + 4 <= count else {
            throw ZipArchiveError.invalidArchive
        }
        return UInt32(self[offset])
            | (UInt32(self[offset + 1]) << 8)
            | (UInt32(self[offset + 2]) << 16)
            | (UInt32(self[offset + 3]) << 24)
    }

    func checkedInt32(at offset: Int) throws -> Int {
        let value = try uint32(at: offset)
        guard value != UInt32.max, value <= UInt32(Int32.max) else {
            throw ZipArchiveError.zip64Unsupported
        }
        return Int(value)
    }

    func subdataChecked(offset: Int, length: Int) throws -> Data {
        guard offset >= 0,
              length >= 0,
              offset + length <= count
        else {
            throw ZipArchiveError.invalidArchive
        }
        return subdata(in: offset..<(offset + length))
    }
}
