import Foundation
import SwiftUI

public enum UserColorGenerator {
    private static let palette: [Color] = [
        Color(red: 0.48, green: 0.38, blue: 1.0),
        Color(red: 0.88, green: 0.48, blue: 0.29),
        Color(red: 0.30, green: 0.69, blue: 0.31),
        Color(red: 0.90, green: 0.30, blue: 0.40),
        Color(red: 0.20, green: 0.60, blue: 0.86),
        Color(red: 0.85, green: 0.65, blue: 0.13),
        Color(red: 0.61, green: 0.35, blue: 0.71),
        Color(red: 0.00, green: 0.74, blue: 0.65),
        Color(red: 0.91, green: 0.38, blue: 0.65),
        Color(red: 0.40, green: 0.73, blue: 0.42),
    ]

    public static func color(for userID: String) -> Color {
        var hash: UInt64 = 5381
        for byte in userID.utf8 {
            hash = hash &* 33 &+ UInt64(byte)
        }
        let index = Int(hash % UInt64(palette.count))
        return palette[index]
    }
}
