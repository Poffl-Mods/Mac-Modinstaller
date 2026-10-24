import Foundation

/// Reads VS_FIXEDFILEINFO from a PE version resource without loading the assembly.
/// https://learn.microsoft.com/windows/win32/debug/pe-format
/// https://learn.microsoft.com/windows/win32/api/verrsrc/ns-verrsrc-vs_fixedfileinfo
struct PEFileVersion {
    static func read(_ bytes: Data) -> String? {
        func number(_ at: Int, _ size: Int) -> Int? {
            guard at >= 0, at <= bytes.count, size <= bytes.count - at else { return nil }
            return (0..<size).reduce(0) { $0 | Int(bytes[at + $1]) << ($1 * 8) }
        }
        guard bytes.starts(with: [0x4d, 0x5a]), let pe = number(0x3c, 4), number(pe, 4) == 0x4550,
            let sections = number(pe + 6, 2), sections <= 96,
            let optionalSize = number(pe + 20, 2), let magic = number(pe + 24, 2),
            [0x10b, 0x20b].contains(magic)
        else { return nil }
        let optional = pe + 24
        let directory = optional + (magic == 0x10b ? 96 : 112)
        guard directory + 24 <= optional + optionalSize,
            let directories = number(directory - 4, 4), directories > 2,
            let resourceRVA = number(directory + 16, 4), resourceRVA > 0,
            let resourceSize = number(directory + 20, 4), resourceSize >= 16
        else { return nil }
        func map(_ rva: Int, size: Int) -> Int? {
            for index in 0..<sections {
                let section = optional + optionalSize + index * 40
                guard let start = number(section + 12, 4), let length = number(section + 16, 4),
                    let raw = number(section + 20, 4)
                else { return nil }
                if rva >= start, rva - start <= length, size <= length - (rva - start),
                    raw + rva - start <= bytes.count, size <= bytes.count - (raw + rva - start)
                {
                    return raw + rva - start
                }
            }
            return nil
        }
        guard let base = map(resourceRVA, size: resourceSize) else { return nil }
        func entries(_ relative: Int) -> [(Int, Int)]? {
            guard relative >= 0, relative <= resourceSize - 16,
                let named = number(base + relative + 12, 2), let ids = number(base + relative + 14, 2),
                named + ids <= (resourceSize - relative - 16) / 8
            else { return nil }
            var result: [(Int, Int)] = []
            for index in 0..<(named + ids) {
                let at = base + relative + 16 + index * 8
                guard let name = number(at, 4), let value = number(at + 4, 4) else { return nil }
                result.append((name, value))
            }
            return result
        }
        guard let type = entries(0)?.first(where: { $0.0 == 16 }), type.1 & 0x8000_0000 != 0,
            let name = entries(type.1 & 0x7fff_ffff)?.first, name.1 & 0x8000_0000 != 0,
            let language = entries(name.1 & 0x7fff_ffff)?.first, language.1 & 0x8000_0000 == 0,
            language.1 <= resourceSize - 16,
            let rva = number(base + language.1, 4), let size = number(base + language.1 + 4, 4),
            size >= 92, let at = map(rva, size: size),
            let length = number(at, 2), length >= 92, length <= size, number(at + 2, 2) == 52,
            number(at + 4, 2) == 0
        else { return nil }
        let key = Array("VS_VERSION_INFO\0".utf16)
        for (index, character) in key.enumerated() {
            guard number(at + 6 + index * 2, 2) == Int(character) else { return nil }
        }
        let fixed = (at + 6 + key.count * 2 + 3) & ~3
        guard fixed + 52 <= at + length, number(fixed, 4) == 0xfeef_04bd,
            let high = number(fixed + 8, 4), let low = number(fixed + 12, 4)
        else { return nil }
        return [high >> 16, high & 0xffff, low >> 16, low & 0xffff].map(String.init).joined(separator: ".")
    }
}
