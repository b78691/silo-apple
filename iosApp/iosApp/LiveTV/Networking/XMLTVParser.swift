import Foundation

final class XMLTVParser: NSObject, XMLParserDelegate, @unchecked Sendable {
    private var programmes: [EPGProgramme] = []
    private var attributes: [String: String] = [:]
    private var element = ""
    private var text = ""
    private var title = ""
    private var subtitle: String?
    private var programmeDescription: String?

    func parse(data: Data) throws -> [EPGProgramme] {
        programmes = []
        let parser = XMLParser(data: data)
        parser.delegate = self
        guard parser.parse() else { throw IPTVError.malformedResponse }
        return programmes
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        element = elementName; text = ""
        if elementName == "programme" { attributes = attributeDict; title = ""; subtitle = nil; programmeDescription = nil }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if elementName == "title" { title = value }
        else if elementName == "sub-title" { subtitle = value }
        else if elementName == "desc" { programmeDescription = value }
        else if elementName == "programme", let channel = attributes["channel"],
                let start = Self.date(attributes["start"]), let end = Self.date(attributes["stop"]), end > start {
            programmes.append(.init(id: "\(channel)-\(Int(start.timeIntervalSince1970))", channelID: channel,
                title: title.isEmpty ? "Programme" : title, subtitle: subtitle, description: programmeDescription, start: start, end: end))
        }
        text = ""
    }

    static func date(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let parts = raw.split(separator: " ", maxSplits: 1).map(String.init)
        let value = parts[0]
        let formats = ["yyyyMMddHHmmss", "yyyyMMddHHmm", "yyyyMMddHH"]
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        if parts.count > 1 { formatter.timeZone = TimeZone(xmlTVOffset: parts[1]) }
        else { formatter.timeZone = .current }
        for format in formats { formatter.dateFormat = format; if let date = formatter.date(from: value) { return date } }
        return nil
    }
}

private extension TimeZone {
    init?(xmlTVOffset: String) {
        guard xmlTVOffset.count >= 5 else { return nil }
        let sign = xmlTVOffset.hasPrefix("-") ? -1 : 1
        let digits = xmlTVOffset.dropFirst().prefix(4)
        guard let hours = Int(digits.prefix(2)), let minutes = Int(digits.suffix(2)) else { return nil }
        self.init(secondsFromGMT: sign * (hours * 3600 + minutes * 60))
    }
}
