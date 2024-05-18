//
//  Logger.swift
//  RealTimeMessengerAPI
//
//  Created by Dmitriy Permyakov on 22.02.2024.
//

import Foundation
import SwiftPrettyPrint

final class Logger {
    private init() {}

    static func log(kind: Kind = .info, message: Any, function: String = #function) {
        print("[ \(kind.rawValue.uppercased()) ]: [ \(Date()) ]: [ \(function) ]")
        Pretty.prettyPrint(message)
        print()
    }

    enum Kind: String {
        case info = "ℹ️ info"
        case error = "⛔️ error"
        case warning = "⚠️ warning"
        case message = "💬 message"
        case close = "❌ close"
        case connection = "✅ open"
    }
}
