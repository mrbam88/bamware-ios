//
//  ObservabilityService.swift.swift
//  BamwareUI
//
//  Created by Bilal Malik on 3/22/25.
//

public protocol ObservabilityService {
    func log(_ message: String, level: LogLevel, metadata: ObservabilityMetadata)
}

public enum LogLevel {
    case info, warning, error
}
