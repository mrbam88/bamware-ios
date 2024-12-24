//
//  SwiftUIView.swift
//  BamwareUI
//
//  Created by Bilal Malik on 12/23/24.
//

import SwiftUI

@available(iOS 13.0, *)
public struct SplashScreen: View {
    public var body: some View {
        VStack {
            Text("Welcome to BamwareUI")
                .font(.largeTitle)
                
        }
    }
}

@available(iOS 13.0, *)
#Preview {
    SplashScreen()
}
