//
//  SerialPortSettings.swift
//  MacSerial
//
//  Created by Tomosawa on 2025/12/19.
//

import Foundation

// 串口配置
struct SerialPortSettings: Codable {
    var baudRate: Int = 115200
    var dataBits: Int = 8
    var stopBits: Int = 1
    var parity: ParityType = .none
    var flowControl: FlowControlType = .none
    
    enum ParityType: String, Codable, CaseIterable {
        case none = "parity_none"
        case odd = "parity_odd"
        case even = "parity_even"
        case mark = "Mark"
        case space = "Space"
        
        var displayName: String {
            switch self {
            case .none: return NSLocalizedString("parity_none", comment: "")
            case .odd: return NSLocalizedString("parity_odd", comment: "")
            case .even: return NSLocalizedString("parity_even", comment: "")
            case .mark: return "Mark"
            case .space: return "Space"
            }
        }
    }
    
    enum FlowControlType: String, Codable, CaseIterable {
        case none = "None"
        case hardware = "Hardware"
        case software = "Software"
        
        var displayName: String { rawValue }
    }
}

// 显示格式
enum DisplayFormat: String, CaseIterable {
    case text = "format_text"
    case hex = "HEX"
    case mixed = "format_mixed"
    
    var displayName: String {
        switch self {
        case .text: return NSLocalizedString("format_text", comment: "")
        case .hex: return "HEX"
        case .mixed: return NSLocalizedString("format_mixed", comment: "")
        }
    }
}

// 换行符类型
enum LineEndingType: String, CaseIterable {
    case none = "line_ending_none"
    case cr = "\\r"
    case lf = "\\n"
    case crlf = "\\r\\n"
    
    var displayName: String {
        switch self {
        case .none: return NSLocalizedString("line_ending_none", comment: "")
        case .cr: return NSLocalizedString("line_ending_cr", comment: "")
        case .lf: return NSLocalizedString("line_ending_lf", comment: "")
        case .crlf: return NSLocalizedString("line_ending_crlf", comment: "")
        }
    }
    
    var bytes: Data {
        switch self {
        case .none: return Data()
        case .cr: return Data([0x0D])
        case .lf: return Data([0x0A])
        case .crlf: return Data([0x0D, 0x0A])
        }
    }
}

// 接收数据项
struct ReceivedDataItem: Identifiable {
    let id = UUID()
    let timestamp: Date
    let data: Data
    let isReceived: Bool // true=接收，false=发送
    
    // 预格式化缓存（懒加载）
    var formattedText: String?
    var formattedHex: String?
    var formattedMixed: String?
    
    init(timestamp: Date, data: Data, isReceived: Bool) {
        self.timestamp = timestamp
        self.data = data
        self.isReceived = isReceived
    }
}
