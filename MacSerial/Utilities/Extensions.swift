//
//  Extensions.swift
//  MacSerial
//
//  Created by Tomosawa on 2025/12/19.
//

import SwiftUI

// Data扩展，方便转换
extension Data {
    var hexString: String {
        map { String(format: "%02X", $0) }.joined(separator: " ")
    }
    
    var asciiString: String {
        String(data: self, encoding: .utf8) ?? ""
    }
}

// 自定义分割视图样式（如果需要）
struct CustomDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.3))
            .frame(height: 1)
    }
}
