//
//  TabManager.swift
//  MacSerial
//
//  Created by Tomosawa on 2025/12/19.
//

import Foundation
import Combine

struct SerialTab: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var manager: SerialPortManager
    
    init(name: String) {
        self.name = name
        self.manager = SerialPortManager()
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: SerialTab, rhs: SerialTab) -> Bool {
        lhs.id == rhs.id
    }
}

class TabManager: ObservableObject {
    @Published var tabs: [SerialTab] = []
    @Published var selectedTab: SerialTab?
    
    init() {
        addNewTab()
    }
    
    func addNewTab() {
        let tabNumber = tabs.count + 1
        let tabName = String(format: NSLocalizedString("serial_port_tab", comment: ""), tabNumber)
        let newTab = SerialTab(name: tabName)
        tabs.append(newTab)
        selectedTab = newTab
    }
    
    func closeTab(_ tab: SerialTab) {
        // 关闭串口连接
        tab.manager.disconnect()
        
        if let index = tabs.firstIndex(of: tab) {
            tabs.remove(at: index)
            
            // 如果关闭的是当前选中的标签，选择相邻的标签
            if selectedTab == tab {
                if !tabs.isEmpty {
                    if index < tabs.count {
                        selectedTab = tabs[index]
                    } else {
                        selectedTab = tabs[index - 1]
                    }
                } else {
                    selectedTab = nil
                }
            }
        }
        
        // 如果没有标签了，创建一个新标签
        if tabs.isEmpty {
            addNewTab()
        }
    }
    
    func renameTab(_ tab: SerialTab, newName: String) {
        if let index = tabs.firstIndex(of: tab) {
            tabs[index].name = newName
        }
    }
}
