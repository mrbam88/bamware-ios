//
//  Theme.swift
//  MyLibrary
//
//  Created by Bilal Malik on 12/23/24.
//

import SwiftUI

public protocol Theme {
    var primaryColor: Color { get }
    var secondaryColor: Color { get }
    var backgroundColor: Color { get }
    var font: Font { get }
    var buttonStyle: ButtonStyle { get }
}
