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
    var placeholderAssignments: [PresentationTemplatePlaceholderAssignment]
}

/// A placeholder shape's position and size, in EMUs, as read from `<a:xfrm>`.
struct OOXMLFrame: Equatable {
    var x: Int
    var y: Int
    var cx: Int
    var cy: Int
}

/// Where a resolved placeholder's effective frame came from in the
/// slide -> slideLayout -> slideMaster inheritance chain.
enum PlaceholderFrameSource: String, Equatable {
    case slide, layout, master, none
}

/// A slide placeholder shape after resolving its effective type, index, and
/// geometry by walking up to the matched slide layout and slide master
/// placeholder shapes, per the ECMA-376 inheritance rules.
struct ResolvedPlaceholder: Equatable {
    var shapeID: Int?
    var shapeName: String?
    var effectiveType: String
    var effectiveIdx: Int
    var effectiveFrame: OOXMLFrame?
    var frameSource: PlaceholderFrameSource
}

struct PresentationTemplatePlaceholderResolution: Equatable {
    var sourceSlideNumber: Int
    var placeholders: [ResolvedPlaceholder]
}

enum PowerPointTemplateInspector {
    static func inspect(url: URL) throws -> PowerPointTemplateInspectionResult {
        let archive = try PowerPointPackageReader(url: url)
        let slideEntries = try sortedSlideEntryNames(in: archive)

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

        // Best-effort: a template that fails placeholder resolution (no discoverable
        // layouts/masters) still has a usable slide inventory and frame map above, so this
        // degrades to no placeholder assignments rather than failing the whole inspection.
        let resolutions = (try? resolvePlaceholders(url: url)) ?? []
        let placeholderAssignments = resolutions.flatMap { resolution in
            resolution.placeholders.compactMap { placeholder -> PresentationTemplatePlaceholderAssignment? in
                // A placeholder with no shape ID can't be structurally addressed later for
                // content placement, so it's omitted rather than assigned a synthetic one.
                guard let shapeID = placeholder.shapeID else { return nil }
                return PresentationTemplatePlaceholderAssignment(
                    id: UUID(),
                    sourceSlideNumber: resolution.sourceSlideNumber,
                    shapeID: shapeID,
                    shapeName: placeholder.shapeName,
                    effectiveType: placeholder.effectiveType,
                    effectiveIdx: placeholder.effectiveIdx,
                    lessonField: nil
                )
            }
        }

        return PowerPointTemplateInspectionResult(
            slideInventory: inventory, frameMap: frameMap, placeholderAssignments: placeholderAssignments
        )
    }

    /// Resolves each slide's placeholder shapes to their effective type, index, and
    /// geometry by walking slide -> slideLayout -> slideMaster, per ECMA-376 §19.3.1.36
    /// and real-world producer behavior (PowerPoint, Keynote, Google Slides exports).
    ///
    /// Scoped to `<p:sp>` placeholder shapes (title/body/subtitle/footer/etc. text
    /// placeholders) — picture and graphic-frame placeholders are not resolved. A slide
    /// with no discoverable layout or master degrades to slide-only geometry rather than
    /// throwing, since layout-preserving fidelity is best-effort against arbitrary
    /// customer-owned templates.
    static func resolvePlaceholders(url: URL) throws -> [PresentationTemplatePlaceholderResolution] {
        let archive = try PowerPointPackageReader(url: url)
        let slideEntries = try sortedSlideEntryNames(in: archive)

        var layoutShapeCache: [String: [OOXMLPlaceholderShape]] = [:]
        var masterShapeCache: [String: [OOXMLPlaceholderShape]] = [:]

        return try slideEntries.enumerated().map { offset, entryName in
            let sourceSlideNumber = offset + 1
            let slideXML = try archive.xml(named: entryName)
            let slideShapes = OOXMLPlaceholderParser.parsePlaceholderShapes(from: slideXML)

            var layoutShapes: [OOXMLPlaceholderShape] = []
            var masterShapes: [OOXMLPlaceholderShape] = []

            if let layoutEntry = resolvedRelationshipTarget(
                for: entryName, relationshipTypeSuffix: "slideLayout", archive: archive
            ) {
                if let cached = layoutShapeCache[layoutEntry] {
                    layoutShapes = cached
                } else if let layoutXML = archive.optionalXML(named: layoutEntry) {
                    layoutShapes = OOXMLPlaceholderParser.parsePlaceholderShapes(from: layoutXML)
                    layoutShapeCache[layoutEntry] = layoutShapes
                }

                if let masterEntry = resolvedRelationshipTarget(
                    for: layoutEntry, relationshipTypeSuffix: "slideMaster", archive: archive
                ) {
                    if let cached = masterShapeCache[masterEntry] {
                        masterShapes = cached
                    } else if let masterXML = archive.optionalXML(named: masterEntry) {
                        masterShapes = OOXMLPlaceholderParser.parsePlaceholderShapes(from: masterXML)
                        masterShapeCache[masterEntry] = masterShapes
                    }
                }
            }

            let resolved = OOXMLPlaceholderResolution.resolve(
                slideShapes: slideShapes, layoutShapes: layoutShapes, masterShapes: masterShapes
            )
            return PresentationTemplatePlaceholderResolution(
                sourceSlideNumber: sourceSlideNumber, placeholders: resolved
            )
        }
    }

    /// Resolves a part's relationship of the given type (matched by suffix, e.g.
    /// "slideLayout" or "slideMaster") to a package-relative entry path, or nil if the
    /// part has no `.rels` file or no relationship of that type — a template's slide or
    /// layout is not guaranteed to have one.
    private static func resolvedRelationshipTarget(
        for partEntry: String, relationshipTypeSuffix: String, archive: PowerPointPackageReader
    ) -> String? {
        let relsEntry = relationshipsEntryName(for: partEntry)
        guard let relsXML = archive.optionalXML(named: relsEntry) else { return nil }
        let relationships = OOXMLRelationshipParser.parse(relsXML)
        guard let relationship = relationships.first(where: { $0.type.hasSuffix(relationshipTypeSuffix) }) else {
            return nil
        }
        return normalizedPackagePath(basePart: partEntry, relativeTarget: relationship.target)
    }

    private static func relationshipsEntryName(for partEntry: String) -> String {
        let components = partEntry.split(separator: "/")
        guard let fileName = components.last else { return partEntry }
        let directory = components.dropLast().joined(separator: "/")
        let relsFileName = "\(fileName).rels"
        return directory.isEmpty ? "_rels/\(relsFileName)" : "\(directory)/_rels/\(relsFileName)"
    }

    /// Resolves a `Target` attribute (relative to `basePart`'s directory, per OPC
    /// conventions) into a package-absolute entry path, collapsing `..` segments.
    private static func normalizedPackagePath(basePart: String, relativeTarget: String) -> String {
        if relativeTarget.hasPrefix("/") { return String(relativeTarget.dropFirst()) }
        var components = basePart.split(separator: "/").dropLast().map(String.init)
        for segment in relativeTarget.split(separator: "/") {
            if segment == ".." {
                if !components.isEmpty { components.removeLast() }
            } else if segment != "." {
                components.append(String(segment))
            }
        }
        return components.joined(separator: "/")
    }

    private static func sortedSlideEntryNames(in archive: PowerPointPackageReader) throws -> [String] {
        let slideEntries = archive.entryNames
            .filter { $0.hasPrefix("ppt/slides/slide") && $0.hasSuffix(".xml") }
            .sorted(by: compareSlideEntryNames)
        guard !slideEntries.isEmpty else { throw PowerPointTemplateInspectionError.missingSlides }
        return slideEntries
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
        if searchable.contains("assessment") || searchable.contains("exit ticket") { return "Assessment" }
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

/// A `<p:ph>` placeholder shape as read directly from one XML part (slide, layout, or
/// master) — `type`/`idx`/`frame` are exactly what that part specifies, `nil` where the
/// part omits them and inheritance from a parent part is expected to fill the gap.
struct OOXMLPlaceholderShape: Equatable {
    var shapeID: Int?
    var shapeName: String?
    var type: String?
    var idx: Int?
    var frame: OOXMLFrame?
}

/// Resolves slide placeholder shapes against their matched slide-layout and slide-master
/// placeholder shapes, per the ECMA-376 inheritance/matching rules: match by `idx` first
/// (falling back to type-match among same-idx candidates when a layout reuses an idx),
/// then by placeholder type, treating `title` and `ctrTitle` as the same slot. A missing
/// `type` defaults to `obj`; a missing `idx` defaults to `0`. Geometry inherits from the
/// nearest ancestor that specifies an `<a:xfrm>` — slide, then layout, then master.
enum OOXMLPlaceholderResolution {
    static func resolve(
        slideShapes: [OOXMLPlaceholderShape],
        layoutShapes: [OOXMLPlaceholderShape],
        masterShapes: [OOXMLPlaceholderShape]
    ) -> [ResolvedPlaceholder] {
        var usedLayoutIndices: Set<Int> = []
        var usedMasterIndices: Set<Int> = []

        return slideShapes.map { slideShape in
            let layoutMatchIndex = matchIndex(for: slideShape, in: layoutShapes, excluding: usedLayoutIndices)
            if let layoutMatchIndex { usedLayoutIndices.insert(layoutMatchIndex) }
            let layoutMatch = layoutMatchIndex.map { layoutShapes[$0] }

            let masterMatchIndex = matchIndex(
                for: layoutMatch ?? slideShape, in: masterShapes, excluding: usedMasterIndices
            )
            if let masterMatchIndex { usedMasterIndices.insert(masterMatchIndex) }
            let masterMatch = masterMatchIndex.map { masterShapes[$0] }

            let frame: OOXMLFrame?
            let frameSource: PlaceholderFrameSource
            if let slideFrame = slideShape.frame {
                frame = slideFrame
                frameSource = .slide
            } else if let layoutFrame = layoutMatch?.frame {
                frame = layoutFrame
                frameSource = .layout
            } else if let masterFrame = masterMatch?.frame {
                frame = masterFrame
                frameSource = .master
            } else {
                frame = nil
                frameSource = .none
            }

            return ResolvedPlaceholder(
                shapeID: slideShape.shapeID,
                shapeName: slideShape.shapeName,
                effectiveType: slideShape.type ?? layoutMatch?.type ?? masterMatch?.type ?? "obj",
                effectiveIdx: slideShape.idx ?? layoutMatch?.idx ?? masterMatch?.idx ?? 0,
                effectiveFrame: frame,
                frameSource: frameSource
            )
        }
    }

    /// `title` and `ctrTitle` are the same conceptual slot for matching purposes; a
    /// missing type defaults to PowerPoint's own default of `obj`.
    private static func normalizedType(_ type: String?) -> String {
        let effective = type ?? "obj"
        return effective == "ctrTitle" ? "title" : effective
    }

    private static func matchIndex(
        for shape: OOXMLPlaceholderShape, in candidates: [OOXMLPlaceholderShape], excluding used: Set<Int>
    ) -> Int? {
        let targetType = normalizedType(shape.type)

        if let idx = shape.idx {
            let idxMatches = candidates.indices.filter { !used.contains($0) && candidates[$0].idx == idx }
            if idxMatches.count == 1 { return idxMatches[0] }
            if idxMatches.count > 1 {
                if let sameType = idxMatches.first(where: { normalizedType(candidates[$0].type) == targetType }) {
                    return sameType
                }
                return idxMatches.first
            }
        }

        return candidates.indices.first { !used.contains($0) && normalizedType(candidates[$0].type) == targetType }
    }
}

private struct OOXMLRelationship {
    var id: String
    var type: String
    var target: String
}

private enum OOXMLRelationshipParser {
    static func parse(_ xml: String) -> [OOXMLRelationship] {
        guard let data = xml.data(using: .utf8) else { return [] }
        let delegate = RelationshipDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.relationships
    }

    private final class RelationshipDelegate: NSObject, XMLParserDelegate {
        var relationships: [OOXMLRelationship] = []

        func parser(
            _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
            qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]
        ) {
            guard elementName == "Relationship",
                  let id = attributeDict["Id"], let type = attributeDict["Type"], let target = attributeDict["Target"]
            else { return }
            relationships.append(OOXMLRelationship(id: id, type: type, target: target))
        }
    }
}

/// Parses `<p:sp>` placeholder shapes out of a slide/layout/master XML part. Deliberately
/// scoped to text-box shapes (`<p:sp>`) — picture and graphic-frame placeholders are not
/// recognized, a safe under-approximation rather than a wrong-geometry result. Does not
/// descend into grouped shapes (`<p:grpSp>`); a placeholder nested inside a group is rare
/// in practice and is skipped rather than mis-parsed.
private enum OOXMLPlaceholderParser {
    static func parsePlaceholderShapes(from xml: String) -> [OOXMLPlaceholderShape] {
        guard let data = xml.data(using: .utf8) else { return [] }
        let delegate = PlaceholderDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.shapes
    }

    private final class PlaceholderDelegate: NSObject, XMLParserDelegate {
        private(set) var shapes: [OOXMLPlaceholderShape] = []

        private var shapeDepth = 0
        private var isInsideSpPr = false
        private var hasPlaceholder = false
        private var currentShapeID: Int?
        private var currentShapeName: String?
        private var currentType: String?
        private var currentIdx: Int?
        private var pendingOffsetX: Int?
        private var pendingOffsetY: Int?
        private var pendingExtentCX: Int?
        private var pendingExtentCY: Int?

        func parser(
            _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
            qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]
        ) {
            switch elementName {
            case "p:sp":
                shapeDepth += 1
                guard shapeDepth == 1 else { return }
                hasPlaceholder = false
                currentShapeID = nil
                currentShapeName = nil
                currentType = nil
                currentIdx = nil
                clearPendingFrame()
            case "p:cNvPr" where shapeDepth == 1:
                currentShapeID = attributeDict["id"].flatMap(Int.init)
                currentShapeName = attributeDict["name"]
            case "p:ph" where shapeDepth == 1:
                hasPlaceholder = true
                currentType = attributeDict["type"]
                currentIdx = attributeDict["idx"].flatMap(Int.init)
            case "p:spPr" where shapeDepth == 1:
                isInsideSpPr = true
                clearPendingFrame()
            case "a:off" where isInsideSpPr:
                pendingOffsetX = attributeDict["x"].flatMap(Int.init)
                pendingOffsetY = attributeDict["y"].flatMap(Int.init)
            case "a:ext" where isInsideSpPr:
                pendingExtentCX = attributeDict["cx"].flatMap(Int.init)
                pendingExtentCY = attributeDict["cy"].flatMap(Int.init)
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            switch elementName {
            case "p:spPr":
                if shapeDepth == 1 { isInsideSpPr = false }
            case "p:sp":
                if shapeDepth == 1, hasPlaceholder {
                    shapes.append(OOXMLPlaceholderShape(
                        shapeID: currentShapeID,
                        shapeName: currentShapeName,
                        type: currentType,
                        idx: currentIdx,
                        frame: resolvedPendingFrame()
                    ))
                }
                shapeDepth = max(0, shapeDepth - 1)
            default:
                break
            }
        }

        private func clearPendingFrame() {
            pendingOffsetX = nil
            pendingOffsetY = nil
            pendingExtentCX = nil
            pendingExtentCY = nil
        }

        private func resolvedPendingFrame() -> OOXMLFrame? {
            guard let x = pendingOffsetX, let y = pendingOffsetY,
                  let cx = pendingExtentCX, let cy = pendingExtentCY
            else { return nil }
            return OOXMLFrame(x: x, y: y, cx: cx, cy: cy)
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

    /// Like `xml(named:)`, but returns `nil` instead of throwing when the entry is
    /// missing or unreadable — for optional parts (a slide's `.rels`, a layout, a master)
    /// that a malformed or partial template may simply not have.
    func optionalXML(named name: String) -> String? {
        try? xml(named: name)
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
