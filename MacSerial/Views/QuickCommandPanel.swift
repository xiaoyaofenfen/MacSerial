//
//  QuickCommandPanel.swift
//  MacSerial
//
//  Created by Tomosawa on 2025/12/19.
//

import SwiftUI

struct QuickCommandPanel: View {
    @Binding var commands: [QuickCommand]
    let onSend: (QuickCommand) -> Void
    let onCommandsChange: () -> Void
    @State private var editingCommand: QuickCommand?
    @State private var showingAddSheet = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 标题栏
            HStack {
                Text(LocalizedStringKey("quick_commands"))
                    .font(.headline)
                Spacer()
                Button(action: { showingAddSheet = true }) {
                    Image(systemName: "plus.circle.fill")
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)
            
            Divider()
            
            // 命令列表
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(commands) { command in
                        QuickCommandRow(
                            command: command,
                            onSend: { onSend(command) },
                            onEdit: { editingCommand = command },
                            onDelete: { deleteCommand(command) }
                        )
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .frame(width: 220)
        .background(Color(NSColor.controlBackgroundColor))
        .sheet(isPresented: $showingAddSheet) {
            CommandEditSheet(
                command: QuickCommand(),
                isPresented: $showingAddSheet,
                onSave: { newCommand in
                    commands.append(newCommand)
                    onCommandsChange()
                }
            )
        }
        .sheet(item: $editingCommand) { command in
            CommandEditSheet(
                command: command,
                isPresented: Binding(
                    get: { editingCommand != nil },
                    set: { if !$0 { editingCommand = nil } }
                ),
                onSave: { updatedCommand in
                    if let index = commands.firstIndex(where: { $0.id == command.id }) {
                        commands[index] = updatedCommand
                        onCommandsChange()
                    }
                }
            )
        }
    }
    
    private func deleteCommand(_ command: QuickCommand) {
        commands.removeAll { $0.id == command.id }
        onCommandsChange()
    }
}

struct QuickCommandRow: View {
    let command: QuickCommand
    let onSend: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 4) {
            Button(action: onSend) {
                HStack {
                    Image(systemName: command.isHex ? "number" : "text.alignleft")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(command.name)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .background(Color.accentColor.opacity(0.1))
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            
            if isHovered {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
            }
        }
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

struct CommandEditSheet: View {
    @State var command: QuickCommand
    @Binding var isPresented: Bool
    let onSave: (QuickCommand) -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Text(LocalizedStringKey("edit_command"))
                .font(.headline)
            
            Form {
                TextField(LocalizedStringKey("command_name"), text: $command.name)
                
                TextEditor(text: $command.command)
                    .frame(height: 100)
                    .border(Color.gray.opacity(0.3))
                
                Toggle(LocalizedStringKey("hex_format"), isOn: $command.isHex)
            }
            .padding()
            
            HStack {
                Button(LocalizedStringKey("cancel")) {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
                
                Button(LocalizedStringKey("save")) {
                    onSave(command)
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 400, height: 280)
    }
}
