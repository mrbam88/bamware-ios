//
//  Theme.swift
//  BamwareUI
//
//  Created by Bilal Malik on 3/22/25.
//
import SwiftUI
import BamwareCore

public protocol Theme: Entity {
    var primaryColor: Color { get }
    var secondaryColor: Color { get }
    var backgroundColor: Color { get }
    var font: Font { get }
    var isDarkMode: Bool { get }
}

// Default Theme
public extension Theme {
    var primaryColor: Color { .blue }
    var secondaryColor: Color { .gray }
    var backgroundColor: Color { .white }
    var font: Font { .body }
    var isDarkMode: Bool { false }
}
