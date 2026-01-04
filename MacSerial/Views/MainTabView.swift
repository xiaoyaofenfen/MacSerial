//
//  MainTabView.swift
//  MacSerial
//
//  Created by Tomosawa on 2025/12/19.
//

import SwiftUI

struct MainTabView: View {
    @StateObject private var tabManager = TabManager()
    
    var body: some View {
        VStack(spacing: 0) {
            // 自定义标签栏
            customTabBar
            
            Divider()
            
            // 使用ZStack保持所有Tab实例，但只有选中的Tab才响应交互
            ZStack {
                ForEach(tabManager.tabs) { tab in
                    SerialPortTabView(
                        manager: tab.manager,
                        isVisible: tabManager.selectedTab == tab
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .opacity(tabManager.selectedTab == tab ? 1 : 0)
                    .allowsHitTesting(tabManager.selectedTab == tab)
                    // 关键优化：使用id让SwiftUI知道这是固定的视图
                    .id(tab.id)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .newTab)) { _ in
            tabManager.addNewTab()
        }
        .onReceive(NotificationCenter.default.publisher(for: .closeTab)) { _ in
            if let selectedTab = tabManager.selectedTab {
                tabManager.closeTab(selectedTab)
            }
        }
    }
    
    private var customTabBar: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(tabManager.tabs) { tab in
                        TabButton(
                            tab: tab,
                            isSelected: tabManager.selectedTab == tab,
                            onSelect: { tabManager.selectedTab = tab },
                            onClose: { tabManager.closeTab(tab) },
                            onRename: { newName in tabManager.renameTab(tab, newName: newName) }
                        )
                    }
                }
                .padding(.leading, 4)
            }
            
            // 新建标签按钮
            Button(action: { tabManager.addNewTab() }) {
                Image(systemName: "plus")
                    .font(.system(size: 12))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help(LocalizedStringKey("new_tab"))
            .padding(.horizontal, 4)
            
            Spacer()
        }
        .frame(height: 32)
        .background(Color(NSColor.controlBackgroundColor))
    }
}

struct TabButton: View {
    let tab: SerialTab
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    let onRename: (String) -> Void
    
    @State private var isHovered = false
    @State private var isEditing = false
    @State private var editingName = ""
    
    var body: some View {
        HStack(spacing: 4) {
            if isEditing {
                TextField("", text: $editingName, onCommit: {
                    if !editingName.isEmpty {
                        onRename(editingName)
                    }
                    isEditing = false
                })
                .textFieldStyle(.plain)
                .frame(width: 100)
                .onAppear {
                    editingName = tab.name
                }
            } else {
                Text(tab.name)
                    .lineLimit(1)
                    .onTapGesture(count: 2) {
                        isEditing = true
                    }
            }
            
            if isHovered && !isEditing {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .help(LocalizedStringKey("close_tab"))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isSelected ? Color(NSColor.controlBackgroundColor) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if !isEditing {
                onSelect()
            }
        }
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
