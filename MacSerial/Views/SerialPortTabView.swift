//
//  SerialPortTabView.swift
//  MacSerial
//
//  Created by Tomosawa on 2025/12/19.
//

import SwiftUI
internal import UniformTypeIdentifiers

struct SerialPortTabView: View {
    @ObservedObject var manager: SerialPortManager
    let isVisible: Bool
    
    @State private var sendText = ""
    @State private var sendFormat: SendFormat = .text
    @State private var lineEnding: LineEndingType = .crlf
    @State private var quickCommands: [QuickCommand] = []
    @State private var showCommandPanel = true
    @State private var autoSend = false
    @State private var autoSendInterval = 1000
    @State private var autoSendTimer: Timer?
    
    enum SendFormat: String, CaseIterable {
        case text = "format_text"
        case hex = "HEX"
        
        var displayName: String {
            switch self {
            case .text: return NSLocalizedString("format_text", comment: "")
            case .hex: return "HEX"
            }
        }
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // 主内容区
            VStack(spacing: 0) {
                // 顶部控制栏
                controlBar
                    .padding(.vertical, 8)
                    .padding(.horizontal, 8)
                    .background(Color(NSColor.controlBackgroundColor))
                
                Divider()
                
                // 接收和发送区域
                VSplitView {
                    // 接收区域
                    receiveArea
                    
                    // 发送区域
                    sendArea
                }
                
                Divider()
                
                // 底部状态栏
                bottomStatusBar
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(NSColor.controlBackgroundColor))
            }
            
            // 右侧快捷命令面板
            if showCommandPanel {
                Divider()
                QuickCommandPanel(
                    commands: $quickCommands,
                    onSend: { command in
                        sendQuickCommand(command)
                    },
                    onCommandsChange: { saveQuickCommands() }
                )
            }
        }
        .onAppear {
            // 只在首次出现时加载快捷命令，避免Tab切换时重复加载
            if quickCommands.isEmpty {
                loadQuickCommands()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .saveLog)) { _ in
            if isVisible {
                saveLog()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .clearReceive)) { _ in
            if isVisible {
                manager.clearReceived()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .clearSend)) { _ in
            if isVisible {
                sendText = ""
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleConnection)) { _ in
            if isVisible {
                toggleConnection()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .refreshPorts)) { _ in
            if isVisible {
                manager.refreshPortList()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleCommandPanel)) { _ in
            if isVisible {
                showCommandPanel.toggle()
            }
        }
        .onDisappear {
         
        }
    }
    
    // MARK: - 控制栏
    private var controlBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // 串口选择
                HStack(spacing: 4) {
                    Text(LocalizedStringKey("serial_port"))
                        .font(.caption)
                        .fixedSize()
                    Picker("", selection: $manager.selectedPort) {
                        ForEach(manager.availablePorts, id: \.self) { port in
                            Text(port.replacingOccurrences(of: "/dev/", with: ""))
                                .tag(port)
                        }
                    }
                    .labelsHidden()
                    .frame(minWidth: 120)
                    
                    Button(action: { manager.refreshPortList() }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .help(LocalizedStringKey("refresh_port_list"))
                }
                
                Divider()
                    .frame(height: 20)
                
                // 波特率
                HStack(spacing: 4) {
                    Text(LocalizedStringKey("baud_rate"))
                        .font(.caption)
                        .fixedSize()
                    Picker("", selection: $manager.settings.baudRate) {
                        Text("9600").tag(9600)
                        Text("19200").tag(19200)
                        Text("38400").tag(38400)
                        Text("57600").tag(57600)
                        Text("115200").tag(115200)
                        Text("230400").tag(230400)
                    }
                    .labelsHidden()
                    .frame(minWidth: 80)
                }
                
                Divider()
                    .frame(height: 20)
                
                // 数据位
                HStack(spacing: 4) {
                    Text(LocalizedStringKey("data_bits"))
                        .font(.caption)
                        .fixedSize()
                    Picker("", selection: $manager.settings.dataBits) {
                        Text("5").tag(5)
                        Text("6").tag(6)
                        Text("7").tag(7)
                        Text("8").tag(8)
                    }
                    .labelsHidden()
                    .frame(minWidth: 50)
                }
                
                Divider()
                    .frame(height: 20)
                
                // 停止位
                HStack(spacing: 4) {
                    Text(LocalizedStringKey("stop_bits"))
                        .font(.caption)
                        .fixedSize()
                    Picker("", selection: $manager.settings.stopBits) {
                        Text("1").tag(1)
                        Text("2").tag(2)
                    }
                    .labelsHidden()
                    .frame(minWidth: 50)
                }
                
                Divider()
                    .frame(height: 20)
                
                // 校验位
                HStack(spacing: 4) {
                    Text(LocalizedStringKey("parity"))
                        .font(.caption)
                        .fixedSize()
                    Picker("", selection: $manager.settings.parity) {
                        ForEach(SerialPortSettings.ParityType.allCases, id: \.self) { parity in
                            Text(parity.displayName).tag(parity)
                        }
                    }
                    .labelsHidden()
                    .frame(minWidth: 70)
                }
                
                Divider()
                    .frame(height: 20)
                
                // 连接/断开按钮
                Button(action: toggleConnection) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(manager.isConnected ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                        Text(manager.isConnected ? LocalizedStringKey("disconnect") : LocalizedStringKey("connect"))
                            .font(.caption)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(manager.isConnected ? .red : .green)
            }
            .padding(.horizontal, 4)
        }
    }
    
    // MARK: - 接收区域
    private var receiveArea: some View {
        VStack(spacing: 0) {
            // 接收区工具栏
            HStack {
                Image(systemName: "arrow.down.circle")
                Text(LocalizedStringKey("receive_area"))
                    .font(.headline)
                
                // 显示数据统计
                if manager.getTotalDataCount() > manager.receivedData.count {
                    Text(String(format: NSLocalizedString("display_latest", comment: ""), manager.receivedData.count, manager.getTotalDataCount()))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Picker("", selection: $manager.displayFormat) {
                    ForEach(DisplayFormat.allCases, id: \.self) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                .frame(width: 100)
                
                Toggle(LocalizedStringKey("timestamp"), isOn: $manager.showTimestamp)
                    .toggleStyle(.checkbox)
                
                Toggle(LocalizedStringKey("auto_scroll"), isOn: $manager.autoScroll)
                    .toggleStyle(.checkbox)
                
                Button(LocalizedStringKey("save_log")) {
                    saveLog()
                }
                
                Button(LocalizedStringKey("clear")) {
                    manager.clearReceived()
                }
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            .zIndex(1)
            
            // 接收数据显示 - 使用高性能NSTextView
            SerialTerminalView(manager: manager, showTimestamp: manager.showTimestamp)
        }
        .frame(minHeight: 200)
    }
    
    
    // MARK: - 发送区域
    private var sendArea: some View {
        VStack(spacing: 0) {
            // 发送区工具栏
            HStack {
                Image(systemName: "arrow.up.circle")
                Text(LocalizedStringKey("send_area"))
                    .font(.headline)
                
                Spacer()
                
                Picker(LocalizedStringKey("send_format"), selection: $sendFormat) {
                    ForEach(SendFormat.allCases, id: \.self) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                .fixedSize()
                
                Picker(LocalizedStringKey("line_ending"), selection: $lineEnding) {
                    ForEach(LineEndingType.allCases, id: \.self) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .fixedSize()
                
                Toggle(LocalizedStringKey("auto_send"), isOn: $autoSend)
                    .toggleStyle(.checkbox)
                    .onChange(of: autoSend) { enabled in
                        toggleAutoSend(enabled)
                    }
                
                if autoSend {
                    TextField("ms", value: $autoSendInterval, format: .number)
                        .fixedSize()
                }
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            
            // 发送输入框
            HStack {
                TextEditor(text: $sendText)
                    .font(.system(.body, design: .monospaced))
                    .border(Color.gray.opacity(0.3))
                    .padding(8)
                
                VStack {
                    Button(LocalizedStringKey("send")) {
                        sendData()
                    }
                    .keyboardShortcut(.return, modifiers: [.command])
                    .buttonStyle(.borderedProminent)
                    .disabled(!manager.isConnected)
                    
                    Button(LocalizedStringKey("clear")) {
                        sendText = ""
                    }
                }
                .padding(.trailing, 8)
            }
        }
        .frame(minHeight: 120)
    }
    
    // MARK: - 状态栏
    private var bottomStatusBar: some View {
        HStack {
            Image(systemName: "chart.bar")
            
            Text("RX: \(formatByteCount(manager.rxByteCount))")
                .font(.system(.caption, design: .monospaced))
            
            Text("TX: \(formatByteCount(manager.txByteCount))")
                .font(.system(.caption, design: .monospaced))
            
            Divider()
                .frame(height: 12)
            
            Text("\(NSLocalizedString("status", comment: "")) \(manager.isConnected ? NSLocalizedString("connected", comment: "") : NSLocalizedString("disconnected", comment: ""))")
                .font(.caption)
            
            if !manager.errorMessage.isEmpty {
                Text(manager.errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .lineLimit(1)
            }
            
            if manager.errorCount > 0 {
                Text("\(NSLocalizedString("errors", comment: "")) \(manager.errorCount)")
                    .font(.caption)
                    .foregroundColor(.red)
            }
            
            Spacer()
            
            Button(LocalizedStringKey("reset_counters")) {
                manager.resetCounters()
            }
            .buttonStyle(.plain)
            .font(.caption)
            
            Button(action: { showCommandPanel.toggle() }) {
                Image(systemName: showCommandPanel ? "sidebar.right" : "sidebar.left")
            }
            .help(showCommandPanel ? LocalizedStringKey("hide_commands") : LocalizedStringKey("show_commands"))
        }
    }
    
    // MARK: - 功能函数
    private func toggleConnection() {
        if manager.isConnected {
            manager.disconnect()
            autoSendTimer?.invalidate()
            autoSendTimer = nil
        } else {
            manager.connect()
        }
    }
    
    private func sendData() {
        guard !sendText.isEmpty else { return }
        
        switch sendFormat {
        case .text:
            manager.sendText(sendText, lineEnding: lineEnding)
        case .hex:
            manager.sendHex(sendText, lineEnding: lineEnding)
        }
    }
    
    private func sendQuickCommand(_ command: QuickCommand) {
        guard manager.isConnected else { return }
        
        // 如果命令为空，不执行（用于分隔符）
        if command.command.trimmingCharacters(in: .whitespaces).isEmpty {
            return
        }
        
        // 支持多行命令序列（用\n分隔）
        let commands = command.command.components(separatedBy: "\n")
        
        for (index, cmd) in commands.enumerated() {
            let trimmedCmd = cmd.trimmingCharacters(in: .whitespaces)
            if trimmedCmd.isEmpty { continue }
            
            // 检查是否是特殊控制指令
            if trimmedCmd.hasPrefix("@") {
                // 特殊控制指令
                switch trimmedCmd.uppercased() {
                case "@RTS_ON":
                    manager.setRTS(true)
                case "@RTS_OFF":
                    manager.setRTS(false)
                case "@DTR_ON":
                    manager.setDTR(true)
                case "@DTR_OFF":
                    manager.setDTR(false)
                default:
                    // 未知的特殊指令，按普通文本发送
                    if command.isHex {
                        manager.sendHex(trimmedCmd, lineEnding: lineEnding)
                    } else {
                        manager.sendText(trimmedCmd, lineEnding: lineEnding)
                    }
                }
            } else {
                // 普通数据发送
                if command.isHex {
                    manager.sendHex(trimmedCmd, lineEnding: lineEnding)
                } else {
                    manager.sendText(trimmedCmd, lineEnding: lineEnding)
                }
            }
            
            // 命令之间延迟50ms，避免执行太快
            if index < commands.count - 1 {
                usleep(50_000)
            }
        }
    }
    
    private func toggleAutoSend(_ enabled: Bool) {
        if enabled {
            autoSendTimer = Timer.scheduledTimer(withTimeInterval: Double(autoSendInterval) / 1000.0, repeats: true) { _ in
                sendData()
            }
        } else {
            autoSendTimer?.invalidate()
            autoSendTimer = nil
        }
    }
    
    private func saveLog() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.text]
        panel.nameFieldStringValue = "serial_log_\(Date().timeIntervalSince1970).txt"
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                // 使用所有数据（而不是只保存显示的数据）
                let allData = manager.getAllData()
                let logContent = allData.map { item in
                    let data = manager.formatData(item.data, format: .text)
                    if manager.showTimestamp {
                        let timestamp = formatTimestamp(item.timestamp)
                        return "[\(timestamp)] \(data)"
                    } else {
                        return data
                    }
                }.joined()
                
                try? logContent.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }
    
    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: date)
    }
    
    private func formatByteCount(_ count: Int) -> String {
        if count < 1024 {
            return "\(count)B"
        } else if count < 1024 * 1024 {
            return String(format: "%.1fKB", Double(count) / 1024.0)
        } else {
            return String(format: "%.1fMB", Double(count) / (1024.0 * 1024.0))
        }
    }
    
    private func loadQuickCommands() {
        if let data = UserDefaults.standard.data(forKey: "quickCommands"),
           let commands = try? JSONDecoder().decode([QuickCommand].self, from: data) {
            quickCommands = commands
            print("✅ 从UserDefaults加载了\(commands.count)条命令")
        } else {
            print("⚠️ 未找到UserDefaults数据或解析失败，加载默认命令")
            // 默认命令
            quickCommands = [
                QuickCommand(name: NSLocalizedString("cmd_control_signals", comment: ""), command: "", isHex: false),
                QuickCommand(name: NSLocalizedString("cmd_rts_high", comment: ""), command: "@RTS_ON", isHex: false),
                QuickCommand(name: NSLocalizedString("cmd_rts_low", comment: ""), command: "@RTS_OFF", isHex: false),
                QuickCommand(name: NSLocalizedString("cmd_dtr_high", comment: ""), command: "@DTR_ON", isHex: false),
                QuickCommand(name: NSLocalizedString("cmd_dtr_low", comment: ""), command: "@DTR_OFF", isHex: false),
                QuickCommand(name: NSLocalizedString("cmd_mcu_control", comment: ""), command: "", isHex: false),
                QuickCommand(name: NSLocalizedString("cmd_restart_chip", comment: ""), command: "@DTR_OFF\n@RTS_ON\n@RTS_OFF", isHex: false),
                QuickCommand(name: NSLocalizedString("cmd_common_commands", comment: ""), command: "", isHex: false),
                QuickCommand(name: NSLocalizedString("cmd_query", comment: ""), command: "AT", isHex: false),
                QuickCommand(name: NSLocalizedString("cmd_reset", comment: ""), command: "AT+RST", isHex: false),
                QuickCommand(name: NSLocalizedString("cmd_version_query", comment: ""), command: "AT+GMR", isHex: false),
                QuickCommand(name: NSLocalizedString("cmd_wifi_scan", comment: ""), command: "AT+CWLAP", isHex: false)
            ]
        }
    }
    
    private func saveQuickCommands() {
        if let data = try? JSONEncoder().encode(quickCommands) {
            UserDefaults.standard.set(data, forKey: "quickCommands")
            print("💾 保存了\(quickCommands.count)条快捷命令")
        }
    }
    
    // 清除UserDefaults中的快捷命令（调试用）
    private func clearQuickCommands() {
        UserDefaults.standard.removeObject(forKey: "quickCommands")
        UserDefaults.standard.synchronize()
        print("🗑️ 已清除UserDefaults中的快捷命令")
        loadQuickCommands()
    }
}
