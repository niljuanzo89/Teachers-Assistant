import Foundation

enum PowerPointTemplateComposerError: LocalizedError, Equatable {
    case unreadableTemplate
    case noAssignedPlaceholders

    var errorDescription: String? {
        switch self {
        case .unreadableTemplate:
            "The presentation template could not be composed."
        case .noAssignedPlaceholders:
            "The presentation template does not have assigned placeholders to compose."
        }
    }
}

enum PowerPointTemplateComposer {
    /// Writes approved lesson content into the teacher-reviewed placeholder assignments
    /// without changing the customer's slide order or package structure. This keeps
    /// template ownership local and layout-preserving: only addressed text placeholder
    /// shapes on existing slides are edited, while every other package part is copied
    /// through as-is at the uncompressed XML/binary content level.
    static func compose(
        templateURL: URL,
        placeholderAssignments: [PresentationTemplatePlaceholderAssignment],
        content: LessonOutputContent
    ) throws -> Data {
        let archive: PowerPointPackageReader
        do {
            archive = try PowerPointPackageReader(url: templateURL)
        } catch {
            throw PowerPointTemplateComposerError.unreadableTemplate
        }

        let assignedBySlide = Dictionary(grouping: placeholderAssignments.compactMap { assignment in
            assignment.lessonField.map { AssignedPlaceholder(assignment: assignment, lessonField: $0) }
        }, by: { $0.assignment.sourceSlideNumber })
        guard !assignedBySlide.isEmpty else {
            throw PowerPointTemplateComposerError.noAssignedPlaceholders
        }

        var writer = StoredPowerPointTemplateZipWriter()
        var appliedAssignmentCount = 0

        do {
            for entryName in archive.entryNames {
                let originalData = try archive.data(named: entryName)
                if let slideNumber = slideNumber(from: entryName),
                   let slideAssignments = assignedBySlide[slideNumber], !slideAssignments.isEmpty {
                    guard var xml = String(data: originalData, encoding: .utf8) else {
                        throw PowerPointTemplateComposerError.unreadableTemplate
                    }
                    for assigned in slideAssignments {
                        let text = mappedText(for: assigned.lessonField, content: content)
                        if replacePlaceholderText(in: &xml, shapeID: assigned.assignment.shapeID, text: text) {
                            appliedAssignmentCount += 1
                        }
                    }
                    try writer.add(entryName, Data(xml.utf8))
                } else {
                    try writer.add(entryName, originalData)
                }
            }
            guard appliedAssignmentCount > 0 else {
                throw PowerPointTemplateComposerError.noAssignedPlaceholders
            }
            return try writer.finalize()
        } catch let error as PowerPointTemplateComposerError {
            throw error
        } catch {
            throw PowerPointTemplateComposerError.unreadableTemplate
        }
    }
}

private struct AssignedPlaceholder {
    var assignment: PresentationTemplatePlaceholderAssignment
    var lessonField: LessonTemplateField
}

private func mappedText(for field: LessonTemplateField, content: LessonOutputContent) -> String {
    switch field {
    case .title:
        content.title
    case .subject:
        content.subject
    case .gradeOrAgeRange:
        content.gradeOrAgeRange
    case .objective:
        content.objective
    case .instructionalSequence:
        content.steps.map(\.displayText).joined(separator: "\n")
    case .materials:
        content.materials.joined(separator: "\n")
    case .differentiationSummary:
        content.differentiation
    case .printableResourcePrompt:
        content.printablePrompt
    case .assessmentSummary:
        content.assessment
    }
}

private func slideNumber(from entryName: String) -> Int? {
    guard entryName.hasPrefix("ppt/slides/slide"), entryName.hasSuffix(".xml") else { return nil }
    let stem = entryName
        .replacingOccurrences(of: "ppt/slides/slide", with: "")
        .replacingOccurrences(of: ".xml", with: "")
    return Int(stem)
}

private func replacePlaceholderText(in xml: inout String, shapeID: Int, text: String) -> Bool {
    var searchRange = xml.startIndex..<xml.endIndex
    while let shapeOpen = nextElementStart("p:sp", in: xml, range: searchRange),
          let shapeRange = elementRange("p:sp", in: xml, openingAt: shapeOpen.lowerBound) {
        let shapeXML = String(xml[shapeRange])
        if shapeHasCNvPrID(shapeXML, shapeID: shapeID),
           let txBodyInnerRange = textBodyInnerRange(in: xml, shapeRange: shapeRange) {
            xml.replaceSubrange(
                txBodyInnerRange,
                with: replacingParagraphChildren(in: String(xml[txBodyInnerRange]), text: text)
            )
            return true
        }
        searchRange = shapeRange.upperBound..<xml.endIndex
    }
    return false
}

private func textBodyInnerRange(in xml: String, shapeRange: Range<String.Index>) -> Range<String.Index>? {
    guard let txBodyOpen = nextElementStart("p:txBody", in: xml, range: shapeRange),
          let txBodyOpenEnd = xml.range(of: ">", range: txBodyOpen.upperBound..<shapeRange.upperBound),
          let txBodyClose = xml.range(of: "</p:txBody>", range: txBodyOpenEnd.upperBound..<shapeRange.upperBound)
    else { return nil }
    return txBodyOpenEnd.upperBound..<txBodyClose.lowerBound
}

private func replacingParagraphChildren(in innerXML: String, text: String) -> String {
    let paragraphs = text
        .split(separator: "\n", omittingEmptySubsequences: false)
        .map { line in
            "<a:p><a:r><a:rPr lang=\"en-US\"/><a:t>\(xmlEscape(String(line)))</a:t></a:r></a:p>"
        }
        .joined()

    var result = ""
    var cursor = innerXML.startIndex
    var searchRange = innerXML.startIndex..<innerXML.endIndex
    var insertedParagraphs = false

    while let paragraphOpen = nextElementStart("a:p", in: innerXML, range: searchRange),
          let paragraphRange = elementRange("a:p", in: innerXML, openingAt: paragraphOpen.lowerBound) {
        result += innerXML[cursor..<paragraphRange.lowerBound]
        if !insertedParagraphs {
            result += paragraphs
            insertedParagraphs = true
        }
        cursor = paragraphRange.upperBound
        searchRange = cursor..<innerXML.endIndex
    }

    result += innerXML[cursor..<innerXML.endIndex]
    if !insertedParagraphs { result += paragraphs }
    return result
}

private func shapeHasCNvPrID(_ shapeXML: String, shapeID: Int) -> Bool {
    var searchRange = shapeXML.startIndex..<shapeXML.endIndex
    while let propertyOpen = nextElementStart("p:cNvPr", in: shapeXML, range: searchRange) {
        guard let tagEnd = shapeXML.range(of: ">", range: propertyOpen.upperBound..<shapeXML.endIndex) else {
            return false
        }
        let startTag = String(shapeXML[propertyOpen.lowerBound..<tagEnd.upperBound])
        if attributeValue(named: "id", in: startTag) == String(shapeID) {
            return true
        }
        searchRange = tagEnd.upperBound..<shapeXML.endIndex
    }
    return false
}

private func attributeValue(named name: String, in startTag: String) -> String? {
    let pattern = "\\b\(NSRegularExpression.escapedPattern(for: name))\\s*=\\s*([\"'])(.*?)\\1"
    guard let regex = try? NSRegularExpression(pattern: pattern),
          let match = regex.firstMatch(in: startTag, range: NSRange(startTag.startIndex..., in: startTag)),
          match.numberOfRanges >= 3,
          let valueRange = Range(match.range(at: 2), in: startTag)
    else { return nil }
    return String(startTag[valueRange])
}

private func nextElementStart(_ elementName: String, in xml: String, range: Range<String.Index>) -> Range<String.Index>? {
    var searchRange = range
    let token = "<\(elementName)"
    while let candidate = xml.range(of: token, range: searchRange) {
        if isElementNameBoundary(after: candidate.upperBound, in: xml) {
            return candidate
        }
        searchRange = candidate.upperBound..<range.upperBound
    }
    return nil
}

private func elementRange(_ elementName: String, in xml: String, openingAt openingIndex: String.Index) -> Range<String.Index>? {
    guard let openingEnd = xml.range(of: ">", range: openingIndex..<xml.endIndex) else { return nil }
    var depth = 1
    var cursor = openingEnd.upperBound
    let closeToken = "</\(elementName)>"

    while cursor < xml.endIndex {
        let remaining = cursor..<xml.endIndex
        let nextOpen = nextElementStart(elementName, in: xml, range: remaining)
        let nextClose = xml.range(of: closeToken, range: remaining)

        switch (nextOpen, nextClose) {
        case let (open?, close?) where open.lowerBound < close.lowerBound:
            depth += 1
            guard let openEnd = xml.range(of: ">", range: open.upperBound..<xml.endIndex) else { return nil }
            cursor = openEnd.upperBound
        case let (_, close?):
            depth -= 1
            if depth == 0 { return openingIndex..<close.upperBound }
            cursor = close.upperBound
        default:
            return nil
        }
    }
    return nil
}

private func isElementNameBoundary(after index: String.Index, in xml: String) -> Bool {
    guard index < xml.endIndex else { return true }
    let character = xml[index]
    return character == ">" || character == "/" || character == " " || character == "\n" || character == "\t"
}

private func xmlEscape(_ value: String) -> String {
    value
        .replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
        .replacingOccurrences(of: "\"", with: "&quot;")
        .replacingOccurrences(of: "'", with: "&apos;")
}

private struct StoredPowerPointTemplateZipWriter {
    private struct Entry {
        var name: String
        var data: Data
        var crc: UInt32
        var offset: UInt32
    }

    private var entries: [Entry] = []
    private var body = Data()

    mutating func add(_ name: String, _ data: Data) throws {
        let nameData = Data(name.utf8)
        guard nameData.count <= Int(UInt16.max), data.count <= Int(UInt32.max), body.count <= Int(UInt32.max) else {
            throw PowerPointTemplateComposerError.unreadableTemplate
        }
        let crc = PowerPointTemplateCRC32.compute(data)
        let offset = UInt32(body.count)
        body.appendUInt32(0x04034b50)
        body.appendUInt16(20)
        body.appendUInt16(0)
        body.appendUInt16(0)
        body.appendUInt16(0)
        body.appendUInt16(0)
        body.appendUInt32(crc)
        body.appendUInt32(UInt32(data.count))
        body.appendUInt32(UInt32(data.count))
        body.appendUInt16(UInt16(nameData.count))
        body.appendUInt16(0)
        body.append(nameData)
        body.append(data)
        entries.append(Entry(name: name, data: data, crc: crc, offset: offset))
    }

    func finalize() throws -> Data {
        guard entries.count <= Int(UInt16.max) else {
            throw PowerPointTemplateComposerError.unreadableTemplate
        }
        var result = body
        guard result.count <= Int(UInt32.max) else {
            throw PowerPointTemplateComposerError.unreadableTemplate
        }
        let centralDirectoryOffset = UInt32(result.count)
        var centralDirectory = Data()
        for entry in entries {
            let nameData = Data(entry.name.utf8)
            centralDirectory.appendUInt32(0x02014b50)
            centralDirectory.appendUInt16(20)
            centralDirectory.appendUInt16(20)
            centralDirectory.appendUInt16(0)
            centralDirectory.appendUInt16(0)
            centralDirectory.appendUInt16(0)
            centralDirectory.appendUInt16(0)
            centralDirectory.appendUInt32(entry.crc)
            centralDirectory.appendUInt32(UInt32(entry.data.count))
            centralDirectory.appendUInt32(UInt32(entry.data.count))
            centralDirectory.appendUInt16(UInt16(nameData.count))
            centralDirectory.appendUInt16(0)
            centralDirectory.appendUInt16(0)
            centralDirectory.appendUInt16(0)
            centralDirectory.appendUInt16(0)
            centralDirectory.appendUInt32(0)
            centralDirectory.appendUInt32(entry.offset)
            centralDirectory.append(nameData)
        }
        guard centralDirectory.count <= Int(UInt32.max) else {
            throw PowerPointTemplateComposerError.unreadableTemplate
        }
        result.append(centralDirectory)
        result.appendUInt32(0x06054b50)
        result.appendUInt16(0)
        result.appendUInt16(0)
        result.appendUInt16(UInt16(entries.count))
        result.appendUInt16(UInt16(entries.count))
        result.appendUInt32(UInt32(centralDirectory.count))
        result.appendUInt32(centralDirectoryOffset)
        result.appendUInt16(0)
        return result
    }
}

private enum PowerPointTemplateCRC32 {
    private static let table: [UInt32] = (0...255).map { value in
        var crc = UInt32(value)
        for _ in 0..<8 {
            crc = (crc & 1) == 1 ? (0xedb88320 ^ (crc >> 1)) : (crc >> 1)
        }
        return crc
    }

    static func compute(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffffffff
        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xff)
            crc = table[index] ^ (crc >> 8)
        }
        return crc ^ 0xffffffff
    }
}

private extension Data {
    mutating func appendUInt16(_ value: UInt16) {
        var littleEndian = value.littleEndian
        append(Data(bytes: &littleEndian, count: MemoryLayout<UInt16>.size))
    }

    mutating func appendUInt32(_ value: UInt32) {
        var littleEndian = value.littleEndian
        append(Data(bytes: &littleEndian, count: MemoryLayout<UInt32>.size))
    }
}
