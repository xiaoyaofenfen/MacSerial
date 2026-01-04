//
//  MacSerialApp.swift
//  MacSerial
//
//  Created by Tomosawa on 2025/12/19.
//

import SwiftUI

@main
struct MacSerialApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            // 文件菜单 - 标签管理
            CommandGroup(replacing: .newItem) {
                Button(LocalizedStringKey("menu_new_tab")) {
                    NotificationCenter.default.post(name: .newTab, object: nil)
                }
                .keyboardShortcut("t", modifiers: [.command])
                
                Button(LocalizedStringKey("menu_close_tab")) {
                    NotificationCenter.default.post(name: .closeTab, object: nil)
                }
                .keyboardShortcut("w", modifiers: [.command])
                
                Divider()
                
                Button(LocalizedStringKey("menu_save_log")) {
                    NotificationCenter.default.post(name: .saveLog, object: nil)
                }
                .keyboardShortcut("s", modifiers: [.command])
            }
            
            // 编辑菜单 - 清空操作
            CommandGroup(after: .pasteboard) {
                Divider()
                
                Button(LocalizedStringKey("menu_clear_receive")) {
                    NotificationCenter.default.post(name: .clearReceive, object: nil)
                }
                .keyboardShortcut("k", modifiers: [.command])
                
                Button(LocalizedStringKey("menu_clear_send")) {
                    NotificationCenter.default.post(name: .clearSend, object: nil)
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])
            }
            
            // 串口菜单
            CommandMenu(LocalizedStringKey("menu_serial")) {
                Button(LocalizedStringKey("menu_connect")) {
                    NotificationCenter.default.post(name: .toggleConnection, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command])
                
                Button(LocalizedStringKey("menu_refresh_ports")) {
                    NotificationCenter.default.post(name: .refreshPorts, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }
            
            // 视图菜单
            CommandGroup(after: .sidebar) {
                Button(LocalizedStringKey("menu_toggle_commands")) {
                    NotificationCenter.default.post(name: .toggleCommandPanel, object: nil)
                }
                .keyboardShortcut("b", modifiers: [.command])
            }
        }
    }
}

// 通知扩展
extension Notification.Name {
    static let newTab = Notification.Name("newTab")
    static let closeTab = Notification.Name("closeTab")
    static let saveLog = Notification.Name("saveLog")
    static let clearReceive = Notification.Name("clearReceive")
    static let clearSend = Notification.Name("clearSend")
    static let toggleConnection = Notification.Name("toggleConnection")
    static let refreshPorts = Notification.Name("refreshPorts")
    static let toggleCommandPanel = Notification.Name("toggleCommandPanel")
}
