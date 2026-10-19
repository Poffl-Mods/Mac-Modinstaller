import Foundation

/// Reads metadata only; never loads Unity assets or executes package code.
/// Format references: UnityFS/SerializedFile layouts and BuildTarget enum:
/// https://github.com/Perfare/AssetStudio/tree/master/AssetStudio
/// Independently implemented, bounded reader; supports UnityFS 6–8, raw/LZ4/LZ4HC.
public struct BundlePlatform: Sendable, Identifiable {
    public let path: String
    public let targets: [Int32]
    public let complete: Bool
    public var id: String { path }
    public var description: String { targets.map(Self.name).joined(separator: ", ") }
    // Only the current desktop macOS target is accepted; legacy PPC/Intel targets
    // remain advisory rather than promising they work with the current player.
    var isMac: Bool { complete && targets == [2] }
    static func name(_ target: Int32) -> String {
        switch target {
        case 2: return "macOS"
        case 3: return "macOS PowerPC (legacy)"
        case 4: return "macOS Intel (legacy)"
        case 27: return "macOS Intel 64 (legacy)"
        case 5: return "Windows 32-bit"
        case 19: return "Windows 64-bit"
        case 17: return "Linux 32-bit"
        case 24: return "Linux 64-bit"
        case 25: return "Linux Universal"
        case 9: return "iOS"
        case 13: return "Android"
        case 20: return "WebGL"
        case 31: return "PlayStation 4"
        case 33: return "Xbox One"
        case 37: return "tvOS"
        case 38: return "Nintendo Switch"
        default: return "BuildTarget \(target)"
        }
    }
}

enum AssetBundleReader {
    enum Invalid: Error { case data }
    static let limit = 64 * 1024 * 1024
    struct Cursor {
        let data: Data
        var offset = 0
        var little = false
        mutating func uint(_ count: Int) throws -> UInt64 {
            let bytes = try take(count)
            return little ? bytes.reversed().reduce(0) { ($0 << 8) | UInt64($1) }
                : bytes.reduce(0) { ($0 << 8) | UInt64($1) }
        }
        mutating func take(_ count: Int) throws -> Data {
            guard count >= 0, offset >= 0, count <= data.count - offset else { throw Invalid.data }
            defer { offset += count }
            return data.subdata(in: offset..<offset + count)
        }
        mutating func string() throws -> String {
            let end = min(data.count, offset + 1024)
            guard offset < end, let zero = data[offset..<end].firstIndex(of: 0),
                  let value = String(data: data[offset..<zero], encoding: .utf8) else { throw Invalid.data }
            offset = zero + 1
            return value
        }
    }
    struct Block { let packed: Int; let size: Int; let codec: Int; let fileOffset: UInt64; let offset: UInt64 }
    struct Node { let offset: UInt64; let size: UInt64; let flags: UInt64 }

    static func inspect(_ file: URL, path: String) -> BundlePlatform {
        do { return BundlePlatform(path: path, targets: try targets(file), complete: true) }
        catch { return BundlePlatform(path: path, targets: [], complete: false) }
    }
    static func targets(_ file: URL) throws -> [Int32] {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        let length = try handle.seekToEnd()
        func read(_ offset: UInt64, _ count: Int) throws -> Data {
            guard count >= 0, count <= limit, offset <= length, UInt64(count) <= length - offset else { throw Invalid.data }
            try handle.seek(toOffset: offset)
            let value = try handle.read(upToCount: count) ?? Data()
            guard value.count == count else { throw Invalid.data }
            return value
        }
        var header = Cursor(data: try read(0, Int(min(length, 4096))))
        guard try header.string() == "UnityFS" else { throw Invalid.data }
        let version = try header.uint(4)
        guard (6...8).contains(version) else { throw Invalid.data }
        _ = try header.string(); _ = try header.string()
        guard try header.uint(8) == length else { throw Invalid.data }
        let packed = Int(try header.uint(4)), unpacked = Int(try header.uint(4))
        let flags = try header.uint(4)
        // Unknown/encryption flags are not interpreted as ordinary UnityFS data.
        guard flags & ~UInt64(0x3ff) == 0, flags & 0x40 != 0 else { throw Invalid.data }
        var start = UInt64(header.offset)
        if version >= 7 { start = (start + 15) & ~15 }
        guard UInt64(packed) <= length else { throw Invalid.data }
        let infoOffset = flags & 0x80 != 0 ? length - UInt64(packed) : start
        var info = Cursor(data: try decode(read(infoOffset, packed), codec: Int(flags & 0x3f), size: unpacked))
        if flags & 0x80 == 0 { start += UInt64(packed) }
        if flags & 0x200 != 0 { start = (start + 15) & ~15 }
        let dataEnd = flags & 0x80 != 0 ? infoOffset : length
        _ = try info.take(16)
        let count = Int(try info.uint(4))
        guard count <= 100_000 else { throw Invalid.data }
        var blocks: [Block] = [], fileOffset = start, logicalOffset: UInt64 = 0
        for _ in 0..<count {
            let size = Int(try info.uint(4)), packed = Int(try info.uint(4)), codec = Int(try info.uint(2))
            guard fileOffset <= dataEnd, UInt64(packed) <= dataEnd - fileOffset,
                  logicalOffset <= UInt64.max - UInt64(size) else { throw Invalid.data }
            blocks.append(Block(packed: packed, size: size, codec: codec & 0x3f, fileOffset: fileOffset, offset: logicalOffset))
            fileOffset += UInt64(packed); logicalOffset += UInt64(size)
        }
        let nodeCount = Int(try info.uint(4))
        guard nodeCount <= 100_000 else { throw Invalid.data }
        var nodes: [Node] = []
        for _ in 0..<nodeCount {
            let offset = try info.uint(8), size = try info.uint(8), flags = try info.uint(4)
            _ = try info.string()
            guard offset <= logicalOffset, size <= logicalOffset - offset else { throw Invalid.data }
            if flags & 4 != 0 { nodes.append(Node(offset: offset, size: size, flags: flags)) }
        }
        guard !nodes.isEmpty else { throw Invalid.data }
        var result = Set<Int32>(), budget = 128 * 1024 * 1024
        var cachedIndex: Int?, cached = Data()
        for node in nodes {
            // Serialized headers plus a bounded Unity version string fit in this prefix.
            let end = node.offset + min(node.size, 512)
            var prefix = Data()
            // Locate the first intersecting block without scanning the whole table
            // for every serialized file in an untrusted archive.
            var lowIndex = 0, highIndex = blocks.count
            while lowIndex < highIndex {
                let middle = lowIndex + (highIndex - lowIndex) / 2
                let block = blocks[middle]
                if block.offset + UInt64(block.size) <= node.offset { lowIndex = middle + 1 }
                else { highIndex = middle }
            }
            var index = lowIndex
            while index < blocks.count && blocks[index].offset < end {
                let block = blocks[index]
                defer { index += 1 }
                if cachedIndex != index {
                    guard block.size > 0, block.size <= budget else { throw Invalid.data }
                    budget -= block.size
                    cached = try decode(read(block.fileOffset, block.packed), codec: block.codec, size: block.size)
                    cachedIndex = index
                }
                let low = Int(max(node.offset, block.offset) - block.offset)
                let high = Int(min(end, block.offset + UInt64(block.size)) - block.offset)
                prefix.append(cached[low..<high])
            }
            result.insert(try serializedTarget(prefix, fileSize: node.size))
        }
        return result.sorted()
    }
    static func serializedTarget(_ data: Data, fileSize: UInt64) throws -> Int32 {
        var reader = Cursor(data: data)
        var metadata = try reader.uint(4), size = try reader.uint(4)
        let version = try reader.uint(4)
        var dataOffset = try reader.uint(4)
        guard (9...22).contains(version) else { throw Invalid.data }
        let endian = try reader.uint(1)
        guard endian <= 1 else { throw Invalid.data }
        _ = try reader.take(3)
        if version >= 22 {
            metadata = try reader.uint(4); size = try reader.uint(8)
            dataOffset = try reader.uint(8); _ = try reader.uint(8)
        }
        guard size == fileSize, dataOffset >= UInt64(reader.offset), dataOffset <= size,
              metadata > 0, metadata <= size else { throw Invalid.data }
        reader.little = endian == 0
        let unity = try reader.string()
        guard unity.range(of: #"^\d+\.\d+\.\d+[abfp]\d+$"#, options: .regularExpression) != nil else { throw Invalid.data }
        let target = Int32(bitPattern: UInt32(try reader.uint(4)))
        guard UInt64(reader.offset) <= dataOffset, UInt64(reader.offset) <= UInt64(version >= 22 ? 48 : 20) + metadata else { throw Invalid.data }
        return target
    }
    static func decode(_ data: Data, codec: Int, size: Int) throws -> Data {
        guard size >= 0, size <= limit else { throw Invalid.data }
        if codec == 0 {
            guard data.count == size else { throw Invalid.data }
            return data
        }
        guard codec == 2 || codec == 3 else { throw Invalid.data }
        // Unity uses raw LZ4 blocks, including overlapping match copies.
        var input = Cursor(data: data), output = Data()
        output.reserveCapacity(size)
        func extended(_ base: Int) throws -> Int {
            var value = base
            if base == 15 {
                var next = 255
                while next == 255 {
                    next = Int(try input.uint(1))
                    guard value <= size - next else { throw Invalid.data }
                    value += next
                }
            }
            return value
        }
        while input.offset < data.count {
            let token = Int(try input.uint(1))
            let literal = try extended(token >> 4)
            guard literal <= size - output.count else { throw Invalid.data }
            output.append(try input.take(literal))
            if input.offset == data.count { break }
            input.little = true
            let distance = Int(try input.uint(2))
            input.little = false
            let match = try extended(token & 15) + 4
            guard distance > 0, distance <= output.count, match <= size - output.count else { throw Invalid.data }
            for _ in 0..<match { output.append(output[output.count - distance]) }
        }
        guard output.count == size else { throw Invalid.data }
        return output
    }
}
