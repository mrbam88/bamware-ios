//
//  Logger.swift
//  BamwareUI
//
//  Created by Bilal Malik on 12/24/24.
//
import Foundation
import SwiftUI
import os

@available(iOS 14.0, *)
public class Logger {
    private let logger = os.Logger(subsystem: "com.bamware", category: "UI")

    public func log(_ message: String, verbosity: OSLogType? = .debug) {
        logger.debug("\(message, privacy: .public)")
    }

    public func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }
}
