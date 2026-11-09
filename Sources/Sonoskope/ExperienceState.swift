import Foundation
import Observation
import SonoskopeCore

enum StatusSection: CaseIterable {
  case overview, trends, issues
  var title: String {
    switch self {
    case .overview: L10n.tr("概览")
    case .trends: L10n.tr("趋势")
    case .issues: L10n.tr("问题记录")
    }
  }
}

/// Only explicit navigation changes the record the user is reading. New live
/// events may update MonitorModel.selectedIncidentID without stealing this selection.
@MainActor @Observable final class StatusNavigation {
  var section: StatusSection = .overview
  var incidentID: UUID?

  func showIncident(_ id: UUID) {
    incidentID = id
    section = .issues
  }

  func showOverview() {
    section = .overview
    incidentID = nil
  }
}

enum OnboardingStep: Int, CaseIterable {
  case welcome, monitoring, ready
  var title: String {
    switch self {
    case .welcome: L10n.tr("认识应用")
    case .monitoring: L10n.tr("选择监测项")
    case .ready: L10n.tr("开始使用")
    }
  }
}

/// Presentation bookkeeping only: never changes capture or permission settings.
struct OnboardingProgress {
  private let defaults: UserDefaults
  static let version = 1
  init(defaults: UserDefaults = .standard) { self.defaults = defaults }
  var shouldPresent: Bool {
    !defaults.bool(forKey: "gettingStartedSeen")
      && defaults.integer(forKey: "onboardingVersion") < Self.version
  }
  func acknowledge() {
    defaults.set(Self.version, forKey: "onboardingVersion")
    defaults.set(true, forKey: "gettingStartedSeen")
  }
}

extension Incident {
  var confidenceLabel: String {
    switch confidence {
    case .observed: L10n.tr("已观测事件")
    case .suspected: L10n.tr("疑似异常")
    case .unknown: L10n.tr("原因未确认")
    }
  }
}
