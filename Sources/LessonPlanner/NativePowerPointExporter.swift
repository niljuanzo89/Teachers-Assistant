import Foundation

enum NativePowerPointExporter: SlideDeckGenerating {
    @MainActor static var availability: SlideDeckAvailability {
        SlideDeckAvailability(
            isAvailable: true,
            title: "Native PowerPoint export ready",
            detail: "The built-in Swift Open XML exporter is available."
        )
    }

    @MainActor static func generate(lesson: LessonRecord, destination: URL, template: OutputTemplateRegistration? = nil) async throws {
        let deck = NativePowerPointDeck(lesson: lesson, template: template)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try deck.packageData().write(to: destination, options: .atomic)
    }
}

private struct NativePowerPointDeck {
    var lesson: LessonRecord
    var template: OutputTemplateRegistration?

    func packageData() throws -> Data {
        var zip = StoredZipWriter()
        let title = xmlEscape(lesson.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Lesson" : lesson.title)
        let objective = xmlEscape(lesson.objective.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Teacher-reviewed objective" : lesson.objective)
        let slides = slideContents(title: title, objective: objective)

        zip.add("[Content_Types].xml", contentTypes(slideCount: slides.count))
        zip.add("_rels/.rels", rootRelationships)
        zip.add("docProps/core.xml", coreProperties(title: title))
        zip.add("docProps/app.xml", appProperties(slideCount: slides.count))
        zip.add("ppt/presentation.xml", presentation(slideCount: slides.count))
        zip.add("ppt/_rels/presentation.xml.rels", presentationRelationships(slideCount: slides.count))
        zip.add("ppt/theme/theme1.xml", theme)
        zip.add("ppt/slideMasters/slideMaster1.xml", slideMaster)
        zip.add("ppt/slideMasters/_rels/slideMaster1.xml.rels", slideMasterRelationships)
        zip.add("ppt/slideLayouts/slideLayout1.xml", slideLayout)
        zip.add("ppt/slideLayouts/_rels/slideLayout1.xml.rels", slideLayoutRelationships)
        for (index, slideContent) in slides.enumerated() {
            let slideNumber = index + 1
            zip.add("ppt/slides/slide\(slideNumber).xml", slide(title: slideContent.title, objective: slideContent.subtitle, body: slideContent.body))
            zip.add("ppt/slides/_rels/slide\(slideNumber).xml.rels", slideRelationships(slideNumber: slideNumber))
            zip.add("ppt/notesSlides/notesSlide\(slideNumber).xml", notes(title: slideContent.title, sourceTitle: title, sourceReferences: sourceReferences))
        }
        return zip.finalize()
    }

    private struct SlideContent {
        var title: String
        var subtitle: String
        var body: String
    }

    private var sourceReferences: [String] {
        lesson.sourceReferences.map(cleaned).filter { !$0.isEmpty }
    }

    private var templateReferences: [String] {
        guard let template else { return [] }
        var lines = [
            "- Presentation template: \(xmlEscape(template.displayName)).",
            "- Template reference: \(xmlEscape(template.reference.path))."
        ]
        if let mappings = template.slotMappings, !mappings.isEmpty {
            let mappedFields = mappings
                .map { "\($0.slotName)=\($0.lessonField.displayName)\($0.required ? " required" : " optional")" }
                .joined(separator: "; ")
            lines.append("- Template mappings: \(xmlEscape(mappedFields)).")
        }
        return lines
    }

    private func slideContents(title: String, objective: String) -> [SlideContent] {
        var slides: [SlideContent] = [
            SlideContent(
                title: title,
                subtitle: objective,
                body: [
                    metadataLine(label: "Subject", value: lesson.subject),
                    metadataLine(label: "Grade", value: lesson.gradeOrAgeRange)
                ].filter { !$0.isEmpty }.joined(separator: "\n")
            )
        ]

        let stepLines = lesson.instructionalSequence
            .flatMap(stepLines)
        for chunk in stepLines.chunked(into: 8) {
            slides.append(SlideContent(
                title: "Instructional Sequence",
                subtitle: objective,
                body: chunk.joined(separator: "\n")
            ))
        }

        let supports = [
            section(title: "Materials", values: lesson.materials),
            section(title: "Differentiation", value: lesson.differentiationSummary)
        ].filter { !$0.isEmpty }.joined(separator: "\n")
        if !supports.isEmpty {
            slides.append(SlideContent(title: "Materials and Supports", subtitle: title, body: supports))
        }

        if let printablePrompt = lesson.printableResourcePrompt.map(cleaned), !printablePrompt.isEmpty {
            slides.append(SlideContent(title: "Student Practice", subtitle: title, body: xmlEscape(printablePrompt)))
        }

        let assessment = cleaned(lesson.assessmentSummary)
        if !assessment.isEmpty {
            slides.append(SlideContent(title: "Assessment", subtitle: title, body: xmlEscape(assessment)))
        }

        return slides
    }

    private func contentTypes(slideCount: Int) -> String {
        let slideOverrides = (1...slideCount).map { index in
            """
              <Override PartName="/ppt/slides/slide\(index).xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>
              <Override PartName="/ppt/notesSlides/notesSlide\(index).xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.notesSlide+xml"/>
            """
        }.joined(separator: "\n")
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
          <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
          <Default Extension="xml" ContentType="application/xml"/>
          <Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>
          <Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>
          <Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/>
          <Override PartName="/ppt/theme/theme1.xml" ContentType="application/vnd.openxmlformats-officedocument.theme+xml"/>
          <Override PartName="/ppt/slideMasters/slideMaster1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideMaster+xml"/>
          <Override PartName="/ppt/slideLayouts/slideLayout1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml"/>
        \(slideOverrides)
        </Types>
        """
    }

    private var rootRelationships: String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="ppt/presentation.xml"/>
          <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
          <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>
        </Relationships>
        """
    }

    private func coreProperties(title: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
          <dc:title>\(title)</dc:title>
          <dc:creator>LessonPlanner</dc:creator>
          <cp:lastModifiedBy>LessonPlanner</cp:lastModifiedBy>
          <dcterms:created xsi:type="dcterms:W3CDTF">2026-07-28T00:00:00Z</dcterms:created>
          <dcterms:modified xsi:type="dcterms:W3CDTF">2026-07-28T00:00:00Z</dcterms:modified>
        </cp:coreProperties>
        """
    }

    private func appProperties(slideCount: Int) -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties" xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes">
          <Application>LessonPlanner</Application>
          <PresentationFormat>On-screen Show (16:9)</PresentationFormat>
          <Slides>\(slideCount)</Slides>
        </Properties>
        """
    }

    private func presentation(slideCount: Int) -> String {
        let slideIDs = (1...slideCount).map { index in
            "    <p:sldId id=\"\(255 + index)\" r:id=\"rId\(index + 1)\"/>"
        }.joined(separator: "\n")
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <p:presentation xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
          <p:sldMasterIdLst><p:sldMasterId id="2147483648" r:id="rId1"/></p:sldMasterIdLst>
          <p:sldIdLst>
        \(slideIDs)
          </p:sldIdLst>
          <p:sldSz cx="12192000" cy="6858000" type="screen16x9"/>
          <p:notesSz cx="6858000" cy="9144000"/>
        </p:presentation>
        """
    }

    private func presentationRelationships(slideCount: Int) -> String {
        let slideRelationships = (1...slideCount).map { index in
            """
              <Relationship Id="rId\(index + 1)" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slides/slide\(index).xml"/>
            """
        }.joined(separator: "\n")
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster" Target="slideMasters/slideMaster1.xml"/>
        \(slideRelationships)
        </Relationships>
        """
    }

    private var theme: String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <a:theme xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" name="LessonPlanner">
          <a:themeElements>
            <a:clrScheme name="LessonPlanner"><a:dk1><a:srgbClr val="202020"/></a:dk1><a:lt1><a:srgbClr val="F4F3F2"/></a:lt1><a:accent1><a:srgbClr val="0088B0"/></a:accent1><a:accent2><a:srgbClr val="D6006C"/></a:accent2><a:accent3><a:srgbClr val="666666"/></a:accent3><a:accent4><a:srgbClr val="FFFFFF"/></a:accent4><a:accent5><a:srgbClr val="000000"/></a:accent5><a:accent6><a:srgbClr val="888888"/></a:accent6><a:hlink><a:srgbClr val="0088B0"/></a:hlink><a:folHlink><a:srgbClr val="D6006C"/></a:folHlink></a:clrScheme>
            <a:fontScheme name="LessonPlanner"><a:majorFont><a:latin typeface="Georgia"/></a:majorFont><a:minorFont><a:latin typeface="Aptos"/></a:minorFont></a:fontScheme>
            <a:fmtScheme name="LessonPlanner"><a:fillStyleLst><a:solidFill><a:schemeClr val="lt1"/></a:solidFill></a:fillStyleLst><a:lnStyleLst><a:ln w="6350"><a:solidFill><a:schemeClr val="accent1"/></a:solidFill></a:ln></a:lnStyleLst><a:effectStyleLst><a:effectStyle><a:effectLst/></a:effectStyle></a:effectStyleLst><a:bgFillStyleLst><a:solidFill><a:schemeClr val="lt1"/></a:solidFill></a:bgFillStyleLst></a:fmtScheme>
          </a:themeElements>
        </a:theme>
        """
    }

    private var slideMaster: String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <p:sldMaster xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
          <p:cSld><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/></p:spTree></p:cSld>
          <p:clrMap bg1="lt1" tx1="dk1" bg2="lt1" tx2="dk1" accent1="accent1" accent2="accent2" accent3="accent3" accent4="accent4" accent5="accent5" accent6="accent6" hlink="hlink" folHlink="folHlink"/>
          <p:sldLayoutIdLst><p:sldLayoutId id="2147483649" r:id="rId1"/></p:sldLayoutIdLst>
        </p:sldMaster>
        """
    }

    private var slideMasterRelationships: String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" Target="../slideLayouts/slideLayout1.xml"/>
          <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme" Target="../theme/theme1.xml"/>
        </Relationships>
        """
    }

    private var slideLayout: String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <p:sldLayout xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" type="blank" preserve="1">
          <p:cSld name="Blank"><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/></p:spTree></p:cSld>
          <p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr>
        </p:sldLayout>
        """
    }

    private var slideLayoutRelationships: String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster" Target="../slideMasters/slideMaster1.xml"/>
        </Relationships>
        """
    }

    private func slide(title: String, objective: String, body: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
          <p:cSld><p:bg><p:bgPr><a:solidFill><a:srgbClr val="F4F3F2"/></a:solidFill></p:bgPr></p:bg><p:spTree>
            <p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/>
            \(textBox(id: 2, name: "Title", x: 685800, y: 914400, cx: 10454600, cy: 900000, text: title, size: 3600, bold: true))
            \(line(id: 3, x: 685800, y: 1905000, cx: 10454600, cy: 0))
            \(textBox(id: 4, name: "Objective", x: 914400, y: 2438400, cx: 10000000, cy: 900000, text: objective, size: 2400, bold: true))
            \(textBox(id: 5, name: "Steps", x: 914400, y: 3657600, cx: 10000000, cy: 1500000, text: body, size: 2000, bold: false))
          </p:spTree></p:cSld>
          <p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr>
        </p:sld>
        """
    }

    private func slideRelationships(slideNumber: Int) -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" Target="../slideLayouts/slideLayout1.xml"/>
          <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/notesSlide" Target="../notesSlides/notesSlide\(slideNumber).xml"/>
        </Relationships>
        """
    }

    private func notes(title: String, sourceTitle: String, sourceReferences: [String]) -> String {
        let references = sourceReferences.isEmpty
            ? "- Local approved LessonPlanner record, \(sourceTitle)."
            : (["- Local approved LessonPlanner record, \(sourceTitle)."] + sourceReferences.map { "- Source reference: \(xmlEscape($0))" }).joined(separator: "\n")
        let templateLines = templateReferences.isEmpty ? "" : "\n" + templateReferences.joined(separator: "\n")
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <p:notes xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
          <p:cSld><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/>
            \(textBox(id: 2, name: "Sources", x: 685800, y: 685800, cx: 5486400, cy: 914400, text: "[Sources]\n\(references)\(templateLines)\n- Slide: \(title).\n[/Sources]", size: 1400, bold: false))
          </p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr>
        </p:notes>
        """
    }

    private func textBox(id: Int, name: String, x: Int, y: Int, cx: Int, cy: Int, text: String, size: Int, bold: Bool) -> String {
        let paragraphs = text.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            "<a:p><a:r><a:rPr lang=\"en-US\" sz=\"\(size)\"\(bold ? " b=\"1\"" : "")/><a:t>\(line)</a:t></a:r></a:p>"
        }.joined()
        return """
        <p:sp><p:nvSpPr><p:cNvPr id="\(id)" name="\(name)"/><p:cNvSpPr txBox="1"/><p:nvPr/></p:nvSpPr><p:spPr><a:xfrm><a:off x="\(x)" y="\(y)"/><a:ext cx="\(cx)" cy="\(cy)"/></a:xfrm><a:noFill/><a:ln><a:noFill/></a:ln></p:spPr><p:txBody><a:bodyPr wrap="square"/><a:lstStyle/>\(paragraphs)</p:txBody></p:sp>
        """
    }

    private func line(id: Int, x: Int, y: Int, cx: Int, cy: Int) -> String {
        """
        <p:sp><p:nvSpPr><p:cNvPr id="\(id)" name="Rule"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr><p:spPr><a:xfrm><a:off x="\(x)" y="\(y)"/><a:ext cx="\(cx)" cy="\(cy)"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom><a:solidFill><a:srgbClr val="0088B0"/></a:solidFill><a:ln><a:noFill/></a:ln></p:spPr></p:sp>
        """
    }

    private func xmlEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    private func cleaned(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func metadataLine(label: String, value: String) -> String {
        let cleanedValue = cleaned(value)
        return cleanedValue.isEmpty ? "" : "\(label): \(xmlEscape(cleanedValue))"
    }

    private func stepLines(_ step: InstructionalStep) -> [String] {
        let title = cleaned(step.title)
        let notes = cleaned(step.notes)
        guard !title.isEmpty || !notes.isEmpty else { return [] }
        if title.isEmpty {
            return ["• \(xmlEscape(notes))"]
        }
        if notes.isEmpty {
            return ["• \(xmlEscape(title))"]
        }
        return ["• \(xmlEscape(title))", "  Notes: \(xmlEscape(notes))"]
    }

    private func section(title: String, values: [String]) -> String {
        let cleanedValues = values.map(cleaned).filter { !$0.isEmpty }
        guard !cleanedValues.isEmpty else { return "" }
        return "\(title):\n" + cleanedValues.map { "• \(xmlEscape($0))" }.joined(separator: "\n")
    }

    private func section(title: String, value: String) -> String {
        let cleanedValue = cleaned(value)
        guard !cleanedValue.isEmpty else { return "" }
        return "\(title):\n\(xmlEscape(cleanedValue))"
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map { start in
            Array(self[start..<Swift.min(start + size, count)])
        }
    }
}

private struct StoredZipWriter {
    private struct Entry {
        var name: String
        var data: Data
        var crc: UInt32
        var offset: UInt32
    }

    private var entries: [Entry] = []
    private var body = Data()

    mutating func add(_ name: String, _ content: String) {
        let data = Data(content.utf8)
        let nameData = Data(name.utf8)
        let crc = CRC32.compute(data)
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

    func finalize() -> Data {
        var result = body
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

private enum CRC32 {
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
