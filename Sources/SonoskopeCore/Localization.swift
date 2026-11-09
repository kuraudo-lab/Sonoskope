import Foundation

public enum AppLanguage: String, CaseIterable, Sendable {
  case english = "en"
  case chinese = "zh-Hans"

  /// Use the first supported language in the user's preference order.
  /// Chinese regional/script variants share one Simplified Chinese translation.
  public static func resolve(_ preferences: [String]) -> AppLanguage {
    for preference in preferences {
      switch preference.replacingOccurrences(of: "_", with: "-").lowercased().split(separator: "-")
        .first
      {
      case "zh": return .chinese
      case "en": return .english
      default: continue
      }
    }
    return .english
  }
}

public enum L10n {
  public static var language: AppLanguage { AppLanguage.resolve(Locale.preferredLanguages) }
  public static var locale: Locale { Locale(identifier: language.rawValue) }
  static let catalogs: [AppLanguage: [String: String]] = Dictionary(
    uniqueKeysWithValues: AppLanguage.allCases.map { language in
      let url = Bundle.module.url(
        forResource: "Localizable", withExtension: "strings",
        subdirectory: nil, localization: language.rawValue)
      let values =
        url.flatMap { try? Data(contentsOf: $0) }.flatMap {
          try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: String]
        } ?? [:]
      return (language, values)
    })

  public static func tr(_ text: LocalizedText) -> String { text.resolved(in: language) }

  static func template(_ key: String, in language: AppLanguage) -> String {
    catalogs[language]?[key] ?? catalogs[.english]?[key] ?? key
  }

  // v0.1.0 stored rendered Chinese strings. Recover known templates while leaving
  // device names, third-party errors, and unknown historical text untouched.
  static func legacy(_ value: String) -> LocalizedText {
    for (key, english) in catalogs[.english] ?? [:] {
      if value == key || value == english { return LocalizedText(key: key) }
    }
    for pattern in legacyPatterns {
      let range = NSRange(value.startIndex..., in: value)
      guard let match = pattern.regex.firstMatch(in: value, range: range) else { continue }
      let arguments = (1..<match.numberOfRanges).compactMap {
        Range(match.range(at: $0), in: value).map { String(value[$0]) }
      }
      return LocalizedText(key: pattern.key, arguments: arguments)
    }
    return LocalizedText(verbatim: value)
  }

  private static let legacyPatterns: [(key: String, regex: NSRegularExpression)] = {
    (catalogs[.english] ?? [:]).sorted { $0.key.count > $1.key.count }.flatMap { key, english in
      [key, english].compactMap { template in
        guard template.contains("%@") else { return nil }
        let pattern =
          "\\A"
          + template.components(separatedBy: "%@")
          .map(NSRegularExpression.escapedPattern(for:)).joined(separator: "(.*?)") + "\\z"
        guard
          let regex = try? NSRegularExpression(
            pattern: pattern, options: [.dotMatchesLineSeparators])
        else { return nil }
        return (key, regex)
      }
    }
  }()
}

/// Persist keys and interpolation values, never a translation tied to one launch.
/// Also decodes the plain-string fields written by v0.1.0.
public struct LocalizedText: Codable, Equatable, Sendable, ExpressibleByStringLiteral,
  ExpressibleByStringInterpolation
{
  public let key: String
  public let arguments: [String]
  public let verbatim: Bool
  public var localized: String { resolved(in: L10n.language) }

  public init(key: String, arguments: [String] = []) {
    self.key = key
    self.arguments = arguments
    self.verbatim = false
  }
  public init(verbatim: String) {
    self.key = verbatim
    self.arguments = []
    self.verbatim = true
  }
  public init(stringLiteral value: String) { self.init(key: value) }
  public init(stringInterpolation: StringInterpolation) {
    self.init(key: stringInterpolation.key, arguments: stringInterpolation.arguments)
  }
  public func resolved(in language: AppLanguage) -> String {
    guard !verbatim else { return key }
    let template = L10n.template(key, in: language)
    guard !arguments.isEmpty else { return template }
    let parts = template.components(separatedBy: "%@")
    guard parts.count == arguments.count + 1 else { return template }
    // Single pass: argument text containing "%@" must not become a placeholder.
    return arguments.enumerated().reduce(parts[0]) { $0 + $1.element + parts[$1.offset + 1] }
  }
  public struct StringInterpolation: StringInterpolationProtocol {
    var key = ""
    var arguments: [String] = []
    public init(literalCapacity: Int, interpolationCount: Int) {
      key.reserveCapacity(literalCapacity)
      arguments.reserveCapacity(interpolationCount)
    }
    public mutating func appendLiteral(_ literal: String) { key += literal }
    public mutating func appendInterpolation<T>(_ value: T) {
      key += "%@"
      arguments.append(String(describing: value))
    }
  }
  private enum CodingKeys: String, CodingKey { case key, arguments, verbatim }
  public init(from decoder: Decoder) throws {
    if let value = try? decoder.singleValueContainer().decode(String.self) {
      self = L10n.legacy(value)
    } else {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      key = try container.decode(String.self, forKey: .key)
      arguments = try container.decodeIfPresent([String].self, forKey: .arguments) ?? []
      verbatim = try container.decodeIfPresent(Bool.self, forKey: .verbatim) ?? false
    }
  }
}

extension Date {
  public func uiFormatted(date: Date.FormatStyle.DateStyle, time: Date.FormatStyle.TimeStyle)
    -> String
  {
    formatted(Date.FormatStyle(date: date, time: time).locale(L10n.locale))
  }
}
