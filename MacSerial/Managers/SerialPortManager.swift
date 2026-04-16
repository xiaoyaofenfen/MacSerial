//
//  SerialPortManager.swift
//  MacSerial
//
//  Created by Tomosawa on 2025/12/19.
//

import Foundation
import Combine
import IOKit
import IOKit.serial

class SerialPortManager: ObservableObject {
    @Published var availablePorts: [String] = []
    @Published var selectedPort: String = ""
    @Published var settings = SerialPortSettings()
    @Published var isConnected = false
    @Published var receivedData: [ReceivedDataItem] = [] // 用于UI显示的数据
    @Published var displayFormat: DisplayFormat = .text
    @Published var showTimestamp = true
    @Published var autoScroll = true
    @Published var rxByteCount: Int = 0
    @Published var txByteCount: Int = 0
    @Published var errorCount: Int = 0
    @Published var errorMessage: String = ""
    @Published var rtsState: Bool = false
    @Published var dtrState: Bool = false
    
    // 完整的数据存储（保留所有数据）
    private var allReceivedData: [ReceivedDataItem] = []
    
    // 显示窗口大小（只显示最新的N条，但保留所有数据）
    private let displayWindowSize = 1000
    
    // 增量格式化缓存
    private var cachedFormattedText = ""
    private var cachedFormattedHex = ""
    private var cachedFormattedMixed = ""
    private var cachedTimestamps = ""
    private var lastFormattedIndex = 0
    
    private var fileDescriptor: Int32 = -1
    private var readSource: DispatchSourceRead?
    private var pendingReceiveBuffer = Data()
    private var pendingReceiveFlushWorkItem: DispatchWorkItem?
    private let receiveFlushDelay: TimeInterval = 0.02 // 接收消息缓冲最大时间20ms，不管是否接收到完整的报文都先展示，减少延迟
    
    init() {
        refreshPortList()
        
        #if DEBUG
        SerialPortDebug.printAvailablePorts()
        #endif
    }
    
    // 刷新串口列表
    func refreshPortList() {
        availablePorts = getSerialPorts()
        if !availablePorts.isEmpty && selectedPort.isEmpty {
            selectedPort = availablePorts[0]
        }
    }
    
    // 获取系统串口列表
    private func getSerialPorts() -> [String] {
        var ports = Set<String>()
        
        func isSupportedSerialPath(_ path: String) -> Bool {
            return path.hasPrefix("/dev/cu.")
                || path.hasPrefix("/dev/tty.")
                || path.hasPrefix("/dev/ttys")
        }
        
        func appendIfSupported(_ path: String) {
            guard isSupportedSerialPath(path) else { return }
            ports.insert(path)
        }
        
        let matchingDict = IOServiceMatching(kIOSerialBSDServiceValue)
        var iterator: io_iterator_t = 0
        
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matchingDict, &iterator)
        if result == KERN_SUCCESS {
            defer { IOObjectRelease(iterator) }
            
            var serialService = IOIteratorNext(iterator)
            while serialService != 0 {
                defer {
                    IOObjectRelease(serialService)
                    serialService = IOIteratorNext(iterator)
                }
                
                if let devicePath = IORegistryEntryCreateCFProperty(
                    serialService,
                    kIOCalloutDeviceKey as CFString,
                    kCFAllocatorDefault,
                    0
                )?.takeRetainedValue() as? String {
                    appendIfSupported(devicePath)
                }
                
                if let devicePath = IORegistryEntryCreateCFProperty(
                    serialService,
                    kIODialinDeviceKey as CFString,
                    kCFAllocatorDefault,
                    0
                )?.takeRetainedValue() as? String {
                    appendIfSupported(devicePath)
                }
            }
        }
        
        // `socat` 在 macOS 上常创建 `/dev/ttys*` 伪终端，这类设备通常不会出现在 IOKit 串口列表里。
        if let devEntries = try? FileManager.default.contentsOfDirectory(atPath: "/dev") {
            for entry in devEntries where entry.hasPrefix("ttys") {
                appendIfSupported("/dev/\(entry)")
            }
        }
        
        return ports.sorted()
    }
    
    // 连接串口
    func connect() {
        guard !selectedPort.isEmpty else {
            errorMessage = NSLocalizedString("select_port", comment: "")
            return
        }
        
        errorMessage = ""
        
        #if DEBUG
        print("\n=== 尝试连接串口 ===")
        print("串口: \(selectedPort)")
        print("波特率: \(settings.baudRate)")
        print("数据位: \(settings.dataBits)")
        print("停止位: \(settings.stopBits)")
        print("校验位: \(settings.parity.displayName)")
        SerialPortDebug.testOpenPort(selectedPort)
        #endif
        
        // 打开串口设备
        fileDescriptor = open(selectedPort, O_RDWR | O_NOCTTY)
        if fileDescriptor == -1 {
            let error = String(cString: strerror(errno))
            errorMessage = "\(NSLocalizedString("cannot_open_port", comment: "")): \(error) (errno: \(errno))"
            errorCount += 1
            print("Failed to open \(selectedPort): \(error)")
            return
        }
        
        print("串口打开成功，文件描述符: \(fileDescriptor)")
        
        // 设置为非阻塞模式
        var flags = fcntl(fileDescriptor, F_GETFL)
        flags |= O_NONBLOCK
        fcntl(fileDescriptor, F_SETFL, flags)
        
        // 配置串口参数
        var options = termios()
        tcgetattr(fileDescriptor, &options)
        
        // 设置波特率 - 使用标准波特率常量
        let baudRateConstant = getBaudRateConstant(settings.baudRate)
        cfsetispeed(&options, baudRateConstant)
        cfsetospeed(&options, baudRateConstant)
        
        // 设置数据位
        options.c_cflag &= ~tcflag_t(CSIZE)
        switch settings.dataBits {
        case 5: options.c_cflag |= tcflag_t(CS5)
        case 6: options.c_cflag |= tcflag_t(CS6)
        case 7: options.c_cflag |= tcflag_t(CS7)
        case 8: options.c_cflag |= tcflag_t(CS8)
        default: options.c_cflag |= tcflag_t(CS8)
        }
        
        // 设置停止位
        if settings.stopBits == 2 {
            options.c_cflag |= tcflag_t(CSTOPB)
        } else {
            options.c_cflag &= ~tcflag_t(CSTOPB)
        }
        
        // 设置校验位
        switch settings.parity {
        case .none:
            options.c_cflag &= ~tcflag_t(PARENB)
        case .odd:
            options.c_cflag |= tcflag_t(PARENB)
            options.c_cflag |= tcflag_t(PARODD)
        case .even:
            options.c_cflag |= tcflag_t(PARENB)
            options.c_cflag &= ~tcflag_t(PARODD)
        default:
            options.c_cflag &= ~tcflag_t(PARENB)
        }
        
        // 启用接收，本地模式
        options.c_cflag |= tcflag_t(CREAD | CLOCAL)
        
        // 原始模式
        options.c_lflag &= ~tcflag_t(ICANON | ECHO | ECHOE | ISIG)
        options.c_oflag &= ~tcflag_t(OPOST)
        options.c_iflag &= ~tcflag_t(INLCR | ICRNL | IXON | IXOFF | IXANY)
        
        // 应用设置
        tcsetattr(fileDescriptor, TCSANOW, &options)
        
        isConnected = true
        
        // 开始读取数据
        startReading()
    }
    
    // 断开串口
    func disconnect() {
        flushPendingReceiveBuffer()
        pendingReceiveFlushWorkItem?.cancel()
        pendingReceiveFlushWorkItem = nil
        
        if fileDescriptor != -1 {
            readSource?.cancel()
            readSource = nil
            close(fileDescriptor)
            fileDescriptor = -1
        }
        isConnected = false
    }
    
    // 开始读取数据
    private func startReading() {
        guard fileDescriptor != -1 else { return }
        
        readSource = DispatchSource.makeReadSource(fileDescriptor: fileDescriptor, queue: .main)
        
        readSource?.setEventHandler { [weak self] in
            guard let self = self else { return }
            
            var buffer = [UInt8](repeating: 0, count: 4096)
            let bytesRead = read(self.fileDescriptor, &buffer, buffer.count)
            
            if bytesRead > 0 {
                let data = Data(buffer[0..<bytesRead])
                self.handleReceivedData(data)
            }
        }
        
        readSource?.resume()
    }

    private func handleReceivedData(_ data: Data) {
        rxByteCount += data.count
        pendingReceiveBuffer.append(data)
        flushCompleteLinesIfNeeded()
        schedulePendingReceiveFlush()
    }
    
    private func flushCompleteLinesIfNeeded() {
        while let range = pendingReceiveBuffer.rangeOfLineTerminator() {
            let message = pendingReceiveBuffer.subdata(in: 0..<range.upperBound)
            appendReceivedItem(message)
            pendingReceiveBuffer.removeSubrange(0..<range.upperBound)
        }
    }
    
    private func schedulePendingReceiveFlush() {
        pendingReceiveFlushWorkItem?.cancel()
        
        let workItem = DispatchWorkItem { [weak self] in
            self?.flushPendingReceiveBuffer()
        }
        
        pendingReceiveFlushWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + receiveFlushDelay, execute: workItem)
    }
    
    private func flushPendingReceiveBuffer() {
        pendingReceiveFlushWorkItem?.cancel()
        pendingReceiveFlushWorkItem = nil
        
        guard !pendingReceiveBuffer.isEmpty else { return }
        appendReceivedItem(pendingReceiveBuffer)
        pendingReceiveBuffer.removeAll(keepingCapacity: true)
    }
    
    private func appendReceivedItem(_ data: Data) {
        let item = ReceivedDataItem(timestamp: Date(), data: data, isReceived: true)
        
        // 保存到完整数据存储
        allReceivedData.append(item)
        
        // 更新显示窗口（只显示最新的数据）
        updateDisplayWindow()
    }
    
    // 发送数据
    func send(data: Data, lineEnding: LineEndingType = .none) {
        guard isConnected, fileDescriptor != -1 else {
            #if DEBUG
            print("❌ 发送失败: 串口未连接")
            #endif
            return
        }
        
        var sendData = data
        sendData.append(lineEnding.bytes)
        
        #if DEBUG
        print("📤 准备发送: \(sendData.count)字节")
        print("📤 数据内容: \(sendData.map { String(format: "%02X", $0) }.joined(separator: " "))")
        #endif
        
        sendData.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) in
            if let baseAddress = ptr.baseAddress {
                let bytesWritten = write(fileDescriptor, baseAddress, sendData.count)
                
                #if DEBUG
                print("📤 write()返回: \(bytesWritten), 期望: \(sendData.count)")
                if bytesWritten < 0 {
                    let error = String(cString: strerror(errno))
                    print("❌ write()错误: \(error) (errno: \(errno))")
                } else if bytesWritten < sendData.count {
                    print("⚠️ 部分发送: 只写入了\(bytesWritten)/\(sendData.count)字节")
                }
                #endif
                
                if bytesWritten > 0 {
                    // 强制刷新输出缓冲区
                    tcdrain(fileDescriptor)
                    
                    DispatchQueue.main.async {
                        self.txByteCount += bytesWritten
                        let item = ReceivedDataItem(timestamp: Date(), data: sendData, isReceived: false)
                        
                        // 保存到完整数据存储
                        self.allReceivedData.append(item)
                        
                        // 更新显示窗口
                        self.updateDisplayWindow()
                    }
                } else {
                    DispatchQueue.main.async {
                        self.errorCount += 1
                        self.errorMessage = "发送失败: \(String(cString: strerror(errno)))"
                    }
                }
            }
        }
    }
    
    // 发送文本
    func sendText(_ text: String, lineEnding: LineEndingType = .none) {
        guard let data = text.data(using: .utf8) else { return }
        #if DEBUG
        print("📤 发送文本: \(text)")
        print("📤 UTF-8字节: \(data.map { String(format: "%02X", $0) }.joined(separator: " "))")
        #endif
        send(data: data, lineEnding: lineEnding)
    }
    
    // 发送HEX
    func sendHex(_ hexString: String, lineEnding: LineEndingType = .none) {
        let data = hexStringToData(hexString)
        send(data: data, lineEnding: lineEnding)
    }
    
    // HEX字符串转Data
    private func hexStringToData(_ hexString: String) -> Data {
        let cleanHex = hexString.replacingOccurrences(of: " ", with: "")
        var data = Data()
        
        var index = cleanHex.startIndex
        while index < cleanHex.endIndex {
            let nextIndex = cleanHex.index(index, offsetBy: 2, limitedBy: cleanHex.endIndex) ?? cleanHex.endIndex
            let byteString = cleanHex[index..<nextIndex]
            if let byte = UInt8(byteString, radix: 16) {
                data.append(byte)
            }
            index = nextIndex
        }
        
        return data
    }
    
    // 更新显示窗口（只显示最新的N条数据）
    private func updateDisplayWindow() {
        let totalCount = allReceivedData.count
        if totalCount <= displayWindowSize {
            receivedData = allReceivedData
        } else {
            let startIndex = totalCount - displayWindowSize
            receivedData = Array(allReceivedData[startIndex..<totalCount])
        }
    }
    
    // 清空接收缓冲
    func clearReceived() {
        pendingReceiveFlushWorkItem?.cancel()
        pendingReceiveFlushWorkItem = nil
        pendingReceiveBuffer.removeAll(keepingCapacity: false)
        allReceivedData.removeAll()
        receivedData.removeAll()
    }
    
    // 获取所有数据（用于导出）
    func getAllData() -> [ReceivedDataItem] {
        return allReceivedData
    }
    
    // 获取总数据条目数
    func getTotalDataCount() -> Int {
        return allReceivedData.count
    }
    
    // 重置计数器
    func resetCounters() {
        rxByteCount = 0
        txByteCount = 0
        errorCount = 0
    }
    
    // 带缓存的格式化（为单个数据项缓存格式化结果）
    func formatDataCached(_ item: inout ReceivedDataItem, format: DisplayFormat) -> String {
        switch format {
        case .text:
            if let cached = item.formattedText {
                return cached
            }
            let result = formatData(item.data, format: .text)
            item.formattedText = result
            return result
        case .hex:
            if let cached = item.formattedHex {
                return cached
            }
            let result = formatData(item.data, format: .hex)
            item.formattedHex = result
            return result
        case .mixed:
            if let cached = item.formattedMixed {
                return cached
            }
            let result = formatData(item.data, format: .mixed)
            item.formattedMixed = result
            return result
        }
    }
    
    // 格式化显示数据
    func formatData(_ data: Data, format: DisplayFormat) -> String {
        switch format {
        case .text:
            var text = String(data: data, encoding: .utf8) ?? ""
            if text.isEmpty {
                return ""
            }
            // 统一换行符：\r\n -> \n, \r -> \n
            text = text.replacingOccurrences(of: "\r\n", with: "\n")
            text = text.replacingOccurrences(of: "\r", with: "\n")
            
            // 确保末尾有换行符
            if !text.hasSuffix("\n") {
                text += "\n"
            }
            return text
            
        case .hex:
            // HEX模式下，每次接收的数据后面加换行符
            if data.isEmpty {
                return ""
            }
            let hexText = data.map { String(format: "%02X ", $0) }.joined()
            return hexText + "\n"
            
        case .mixed:
            var text = String(data: data, encoding: .utf8) ?? ""
            let hex = data.map { String(format: "%02X", $0) }.joined(separator: " ")
            if text.isEmpty && hex.isEmpty {
                return ""
            }
            
            // 统一换行符
            text = text.replacingOccurrences(of: "\r\n", with: "\n")
            text = text.replacingOccurrences(of: "\r", with: "\n")
            
            var mixed = "\(text) [\(hex)]"
            // 确保末尾有换行符
            if !mixed.hasSuffix("\n") {
                mixed += "\n"
            }
            return mixed
        }
    }
    
    // 设置RTS信号
    func setRTS(_ value: Bool) {
        guard isConnected, fileDescriptor != -1 else { return }
        
        var status: Int32 = 0
        ioctl(fileDescriptor, TIOCMGET, &status)
        
        if value {
            status |= TIOCM_RTS
        } else {
            status &= ~TIOCM_RTS
        }
        
        ioctl(fileDescriptor, TIOCMSET, &status)
        rtsState = value
        
        #if DEBUG
        print("🔌 RTS设置为: \(value ? "高" : "低")")
        #endif
    }
    
    // 设置DTR信号
    func setDTR(_ value: Bool) {
        guard isConnected, fileDescriptor != -1 else { return }
        
        var status: Int32 = 0
        ioctl(fileDescriptor, TIOCMGET, &status)
        
        if value {
            status |= TIOCM_DTR
        } else {
            status &= ~TIOCM_DTR
        }
        
        ioctl(fileDescriptor, TIOCMSET, &status)
        dtrState = value
        
        #if DEBUG
        print("🔌 DTR设置为: \(value ? "高" : "低")")
        #endif
    }
    
    // 将波特率数值转换为系统常量
    private func getBaudRateConstant(_ baudRate: Int) -> speed_t {
        switch baudRate {
        case 9600: return speed_t(B9600)
        case 19200: return speed_t(B19200)
        case 38400: return speed_t(B38400)
        case 57600: return speed_t(B57600)
        case 115200: return speed_t(B115200)
        case 230400: return speed_t(B230400)
        default: return speed_t(B115200)
        }
    }
    
    deinit {
        disconnect()
    }
}

private extension Data {
    func rangeOfLineTerminator() -> Range<Data.Index>? {
        guard let newlineIndex = firstIndex(of: 0x0A) ?? firstIndex(of: 0x0D) else {
            return nil
        }
        
        let nextIndex = index(after: newlineIndex)
        
        if self[newlineIndex] == 0x0D,
           nextIndex < endIndex,
           self[nextIndex] == 0x0A {
            return startIndex..<index(after: nextIndex)
        }
        
        return startIndex..<nextIndex
    }
}
