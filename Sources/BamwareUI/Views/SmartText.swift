// SmartText.swift (Body unchanged—Preview only)
import SwiftUI
import BamwareCore


public struct SmartText: View {
    public let text: String  // Public—testable
    public let theme: any Theme
    
    public init(_ text: String, theme: any Theme = DefaultTheme(tenantID: "bamSocial")) {
        self.text = text
        self.theme = theme
    }
    
    public var body: some View {
        Text(text)
            .foregroundColor(theme.primaryColor)
            .font(theme.font)
    }
}
struct SmartText_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            SmartText("Yo, brah!", theme: BrandingPalette.theme(for: "bamSocial", isDarkMode: false))
                .previewDisplayName("bamSocial Light")
            
            SmartText("Yo, brah!", theme: BrandingPalette.theme(for: "bamSocial", isDarkMode: true))
                .previewDisplayName("bamSocial Dark")
            
            SmartText("Hey, cutie!", theme: BrandingPalette.theme(for: "bamMatch", isDarkMode: false))
                .previewDisplayName("bamMatch Light")
            
            SmartText("Hey, cutie!", theme: BrandingPalette.theme(for: "bamMatch", isDarkMode: true))
                .previewDisplayName("bamMatch Dark")
        }
        .previewLayout(.sizeThatFits)
        .previewDevice(nil)  // No device frame—raw text
    }
}
