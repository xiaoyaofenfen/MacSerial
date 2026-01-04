//
//  QuickCommand.swift
//  MacSerial
//
//  Created by Tomosawa on 2025/12/19.
//

import Foundation

struct QuickCommand: Identifiable, Codable {
    var id = UUID()
    var name: String
    var command: String
    var isHex: Bool
    
    init(name: String = NSLocalizedString("new_command", comment: ""), command: String = "", isHex: Bool = false) {
        self.name = name
        self.command = command
        self.isHex = isHex
    }
}
