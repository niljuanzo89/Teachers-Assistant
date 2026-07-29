import Foundation

enum PowerPointTemplateInspectionError: LocalizedError, Equatable {
    case unreadablePackage
    case missingSlides
    case unsupportedCompression(method: UInt16)

    var errorDescription: String? {
        switch self {
        case .unreadablePackage:
            "The presentation template could not be inspected."
        case .missingSlides:
            "The presentation template does not contain readable slides."
        case .unsupportedCompression(let method):
            "The presentation template uses unsupported ZIP compression method \(method)."
        }
    }
}

struct PowerPointTemplateInspectionResult: Equatable {
    var slideInventory: [PresentationTemplateSlideInventoryItem]
    var frameMap: [PresentationTemplateFrameMapEntry]
}

enum PowerPointTemplateInspector {
    static func inspect(url: URL) throws -> PowerPointTemplateInspectionResult {
        let archive = try PowerPointPackageReader(url: url)
        let slideEntries = archive.entryNames
            .filter { $0.hasPrefix("ppt/slides/slide") && $0.hasSuffix(".xml") }
            .sorted(by: compareSlideEntryNames)

        guard !slideEntries.isEmpty else { throw PowerPointTemplateInspectionError.missingSlides }

        let inventory = try slideEntries.enumerated().map { offset, entryName in
            let sourceSlideNumber = offset + 1
            let xml = try archive.xml(named: entryName)
            let title = firstShapeName(in: xml) ?? "Slide \(sourceSlideNumber)"
            let placeholderCount = countPlaceholderMarkers(in: xml)
            return PresentationTemplateSlideInventoryItem(
                id: UUID(),
                sourceSlideNumber: sourceSlideNumber,
                reusableRole: inferredReusableRole(slideNumber: sourceSlideNumber, title: title, xml: xml),
                placeholderCount: placeholderCount,
                notes: "Initial inventory generated from \(entryName)."
            )
        }

        let frameMap = inventory.enumerated().map { offset, item in
            PresentationTemplateFrameMapEntry(
                id: UUID(),
                outputSlideNumber: offset + 1,
                sourceSlideNumber: item.sourceSlideNumber,
                narrativeRole: item.reusableRole,
                mappedSlotNames: inferredSlotNames(for: item.reusableRole, slideNumber: item.sourceSlideNumber),
                notes: "Candidate frame map generated from source slide \(item.sourceSlideNumber)."
            )
        }

        return PowerPointTemplateInspectionResult(slideInventory: inventory, frameMap: frameMap)
    }

    private static func compareSlideEntryNames(_ left: String, _ right: String) -> Bool {
        slideNumber(from: left) < slideNumber(from: right)
    }

    private static func slideNumber(from entryName: String) -> Int {
        let stem = entryName
            .replacingOccurrences(of: "ppt/slides/slide", with: "")
            .replacingOccurrences(of: ".xml", with: "")
        return Int(stem) ?? .max
    }

    private static func countPlaceholderMarkers(in xml: String) -> Int {
        xml.components(separatedBy: "<p:ph").count - 1
    }

    private static func firstShapeName(in xml: String) -> String? {
        guard let range = xml.range(of: "name=\"") else { return nil }
        let tail = xml[range.upperBound...]
        guard let end = tail.firstIndex(of: "\"") else { return nil }
        let name = String(tail[..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    private static func inferredReusableRole(slideNumber: Int, title: String, xml: String) -> String {
        let searchable = "\(title) \(xml)".lowercased()
        if slideNumber == 1 { return "Opening" }
        if searchable.contains("assessment") { return "Assessment" }
        if searchable.contains("practice") { return "Student practice" }
        if searchable.contains("material") || searchable.contains("support") { return "Materials and supports" }
        if searchable.contains("differentiation") { return "Differentiation" }
        return "Instruction"
    }

    private static func inferredSlotNames(for role: String, slideNumber: Int) -> [String] {
        switch role {
        case "Opening":
            ["lesson.title", "lesson.objective"]
        case "Assessment":
            ["lesson.assessment"]
        case "Student practice":
            ["lesson.practice"]
        case "Materials and supports":
            ["lesson.materials", "lesson.differentiation"]
        case "Differentiation":
            ["lesson.differentiation"]
        default:
            slideNumber == 1 ? ["lesson.title", "lesson.objective"] : ["lesson.steps"]
        }
    }
}

private struct PowerPointPackageReader {
    private struct Entry {
        var name: String
        var compressionMethod: UInt16
        var compressedSize: Int
        var uncompressedSize: Int
        var localHeaderOffset: Int
    }

    private let data: Data
    private let entries: [Entry]

    var entryNames: [String] { entries.map(\.name) }

    init(url: URL) throws {
        data = try Data(contentsOf: url)
        entries = try Self.readCentralDirectory(from: data)
    }

    func xml(named name: String) throws -> String {
        guard let entry = entries.first(where: { $0.name == name }) else {
            throw PowerPointTemplateInspectionError.unreadablePackage
        }
        let fileData = try dataForEntry(entry)
        guard let xml = String(data: fileData, encoding: .utf8) else {
            throw PowerPointTemplateInspectionError.unreadablePackage
        }
        return xml
    }

    private func dataForEntry(_ entry: Entry) throws -> Data {
        let offset = entry.localHeaderOffset
        guard data.uint32(at: offset) == 0x04034b50 else {
            throw PowerPointTemplateInspectionError.unreadablePackage
        }
        let fileNameLength = Int(data.uint16(at: offset + 26))
        let extraLength = Int(data.uint16(at: offset + 28))
        let bodyStart = offset + 30 + fileNameLength + extraLength
        let bodyEnd = bodyStart + entry.compressedSize
        guard bodyStart >= 0, bodyEnd <= data.count else {
            throw PowerPointTemplateInspectionError.unreadablePackage
        }
        let body = data.subdata(in: bodyStart..<bodyEnd)
        switch entry.compressionMethod {
        case 0:
            return body
        case 8:
            do {
                return try (body as NSData).decompressed(using: .zlib) as Data
            } catch {
                throw PowerPointTemplateInspectionError.unreadablePackage
            }
        default:
            throw PowerPointTemplateInspectionError.unsupportedCompression(method: entry.compressionMethod)
        }
    }

    private static func readCentralDirectory(from data: Data) throws -> [Entry] {
        guard let endRecordOffset = findEndOfCentralDirectory(in: data) else {
            throw PowerPointTemplateInspectionError.unreadablePackage
        }
        let entryCount = Int(data.uint16(at: endRecordOffset + 10))
        let centralDirectoryOffset = Int(data.uint32(at: endRecordOffset + 16))
        var entries: [Entry] = []
        var offset = centralDirectoryOffset
        for _ in 0..<entryCount {
            guard offset + 46 <= data.count, data.uint32(at: offset) == 0x02014b50 else {
                throw PowerPointTemplateInspectionError.unreadablePackage
            }
            let compressionMethod = data.uint16(at: offset + 10)
            let compressedSize = Int(data.uint32(at: offset + 20))
            let uncompressedSize = Int(data.uint32(at: offset + 24))
            let fileNameLength = Int(data.uint16(at: offset + 28))
            let extraLength = Int(data.uint16(at: offset + 30))
            let commentLength = Int(data.uint16(at: offset + 32))
            let localHeaderOffset = Int(data.uint32(at: offset + 42))
            let nameStart = offset + 46
            let nameEnd = nameStart + fileNameLength
            guard nameEnd <= data.count,
                  let name = String(data: data.subdata(in: nameStart..<nameEnd), encoding: .utf8)
            else {
                throw PowerPointTemplateInspectionError.unreadablePackage
            }
            entries.append(Entry(
                name: name,
                compressionMethod: compressionMethod,
                compressedSize: compressedSize,
                uncompressedSize: uncompressedSize,
                localHeaderOffset: localHeaderOffset
            ))
            offset = nameEnd + extraLength + commentLength
        }
        return entries.filter { $0.uncompressedSize > 0 }
    }

    private static func findEndOfCentralDirectory(in data: Data) -> Int? {
        guard data.count >= 22 else { return nil }
        let minimumOffset = max(0, data.count - 65_557)
        var offset = data.count - 22
        while offset >= minimumOffset {
            if data.uint32(at: offset) == 0x06054b50 { return offset }
            offset -= 1
        }
        return nil
    }
}

private extension Data {
    func uint16(at offset: Int) -> UInt16 {
        guard offset + 2 <= count else { return 0 }
        return self[offset..<offset + 2].enumerated().reduce(UInt16(0)) { result, pair in
            result | (UInt16(pair.element) << UInt16(pair.offset * 8))
        }
    }

    func uint32(at offset: Int) -> UInt32 {
        guard offset + 4 <= count else { return 0 }
        return self[offset..<offset + 4].enumerated().reduce(UInt32(0)) { result, pair in
            result | (UInt32(pair.element) << UInt32(pair.offset * 8))
        }
    }
}
