//
//  DefaultTheme.swift
//  MyLibrary
//
//  Created by Bilal Malik on 12/23/24.
//

import SwiftUI

@available(iOS 13.0, *)
public struct DefaultTheme: Theme {
    public var buttonStyle: any ButtonStyle
    public let primaryColor = Color.blue
    public let secondaryColor = Color.gray
    public let backgroundColor = Color.white
    public let font = Font.body
}
