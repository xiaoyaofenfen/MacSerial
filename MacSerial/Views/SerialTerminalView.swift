//
//  SerialTerminalView.swift
//  MacSerial
//
//  Created by Tomosawa on 2025/12/31.
//

import SwiftUI
import AppKit
import Combine

/// 不响应滚动事件的ScrollView（用于时间戳列）
class NonScrollableScrollView: NSScrollView {
    override func scrollWheel(with event: NSEvent) {
        // 不处理滚动事件，让事件向上传递
        nextResponder?.scrollWheel(with: event)
    }
}

/// 高性能串口终端视图（使用NSTextView）
struct SerialTerminalView: View {
    @ObservedObject var manager: SerialPortManager
    let showTimestamp: Bool
    @StateObject private var scrollCoordinator = ScrollCoordinator()
    
    var body: some View {
        HStack(spacing: 0) {
            // 左侧时间戳列
            if showTimestamp {
                TimestampColumn(manager: manager, scrollCoordinator: scrollCoordinator)
                    .frame(width: 130)
                
                Divider()
            }
            
            // 右侧数据列
            DataColumn(manager: manager, scrollCoordinator: scrollCoordinator)
        }
    }
}

/// 滚动同步协调器
class ScrollCoordinator: ObservableObject {
    weak var timestampScrollView: NSScrollView?
    weak var dataScrollView: NSScrollView?
    private var isUpdating = false
    
    func setupSync() {
        // 监听数据列的滚动事件
        if let clipView = dataScrollView?.contentView {
            clipView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: clipView,
                queue: .main
            ) { [weak self] _ in
                self?.syncTimestampScroll()
            }
        }
    }
    
    private func syncTimestampScroll() {
        guard !isUpdating,
              let dataClipView = dataScrollView?.contentView,
              let timestampClipView = timestampScrollView?.contentView else { return }
        
        let dataOrigin = dataClipView.bounds.origin
        let timestampOrigin = timestampClipView.bounds.origin
        
        // 只在Y坐标不同时才同步
        if abs(dataOrigin.y - timestampOrigin.y) > 0.5 {
            isUpdating = true
            
            var newTimestampOrigin = timestampOrigin
            newTimestampOrigin.y = dataOrigin.y
            timestampClipView.setBoundsOrigin(newTimestampOrigin)
            
            isUpdating = false
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

/// 时间戳列
struct TimestampColumn: NSViewRepresentable {
    @ObservedObject var manager: SerialPortManager
    @ObservedObject var scrollCoordinator: ScrollCoordinator
    
    func makeNSView(context: Context) -> NSScrollView {
        // 使用自定义的不响应滚动的ScrollView
        let scrollView = NonScrollableScrollView()
        let textView = NSTextView(frame: .zero)
        
        // 配置文本视图
        textView.isEditable = false
        textView.isSelectable = false  // 时间戳列不可选择
        textView.font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.backgroundColor = NSColor.controlBackgroundColor
        textView.textColor = NSColor.secondaryLabelColor
        textView.drawsBackground = true
        textView.alignment = .right
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        
        // 设置文本容器
        if let textContainer = textView.textContainer {
            textContainer.widthTracksTextView = true
            textContainer.heightTracksTextView = false
            textContainer.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        }
        
        scrollView.documentView = textView
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = false
        
        // 配置滚动视图
        scrollView.hasHorizontalScroller = true  // 显示横向滚动条区域以保持与右侧对齐
        scrollView.hasVerticalScroller = false  // 跟随右侧滚动
        scrollView.autohidesScrollers = false  // 保持横向滚动条区域始终显示
        scrollView.horizontalScroller?.alphaValue = 0  // 隐藏滚动条但保留空间
        scrollView.backgroundColor = NSColor.controlBackgroundColor
        scrollView.drawsBackground = true
        
        // 禁用时间戳列的滚动事件（不响应鼠标滚轮）
        scrollView.scrollerStyle = .overlay
        scrollView.verticalScrollElasticity = .none
        scrollView.horizontalScrollElasticity = .none
        scrollView.contentView.postsBoundsChangedNotifications = false  // 禁用自身滚动通知
        
        // 保存上下文
        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView
        
        // 注册到滚动协调器
        scrollCoordinator.timestampScrollView = scrollView
        
        // 立即显示初始内容
        let initialText = context.coordinator.getTimestamps(manager: manager, format: manager.displayFormat)
        textView.string = initialText
        
        #if DEBUG
        print("⏰ 时间戳初始化: 文本长度=\(initialText.count)")
        #endif
        
        return scrollView
    }
    
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }
        
        let newText = context.coordinator.getTimestamps(manager: manager, format: manager.displayFormat)
        
        if textView.string != newText {
            textView.string = newText
            
            // 强制布局更新
            textView.layoutManager?.ensureLayout(for: textView.textContainer!)
            textView.setNeedsDisplay(textView.visibleRect)
            
            // 如果需要自动滚动，等待布局完成后再同步滚动位置
            if manager.autoScroll {
                DispatchQueue.main.async { [weak scrollView] in
                    scrollView?.documentView?.layoutSubtreeIfNeeded()
                }
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator {
        weak var textView: NSTextView?
        weak var scrollView: NSScrollView?
        
        func getTimestamps(manager: SerialPortManager, format: DisplayFormat) -> String {
            let items = manager.receivedData.filter { $0.isReceived }
            guard !items.isEmpty else { return "" }
            
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss.SSS"
            
            var result: [String] = []
            for item in items {
                let timestamp = formatter.string(from: item.timestamp)
                let formattedData = manager.formatData(item.data, format: format)
                let lineCount = formattedData.filter { $0 == "\n" }.count
                
                // 为每一行添加相同的时间戳
                for _ in 0..<lineCount {
                    result.append(timestamp)
                }
            }
            
            // 在末尾添加换行符以匹配数据列的最后空行
            let timestampText = result.joined(separator: "\n")
            return timestampText.isEmpty ? "" : timestampText + "\n"
        }
    }
}

/// 数据列
struct DataColumn: NSViewRepresentable {
    @ObservedObject var manager: SerialPortManager
    @ObservedObject var scrollCoordinator: ScrollCoordinator
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView
        
        // 配置文本视图
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.textColor = NSColor.textColor
        textView.drawsBackground = true
        
        // 禁用自动换行，启用横向滚动
        textView.isHorizontallyResizable = true
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        
        // 配置滚动视图
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.backgroundColor = NSColor.textBackgroundColor
        scrollView.drawsBackground = true
        
        // 保存上下文
        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView
        
        // 注册到滚动协调器并设置同步
        scrollCoordinator.dataScrollView = scrollView
        scrollCoordinator.setupSync()
        
        // 立即显示初始内容
        let initialText = context.coordinator.getFormattedText(manager: manager, format: manager.displayFormat)
        textView.string = initialText
        
        #if DEBUG
        print("📝 SerialTerminalView makeNSView: 初始文本长度=\(initialText.count)")
        #endif
        
        return scrollView
    }
    
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }
        
        // 检查是否需要更新
        let newText = context.coordinator.getFormattedText(manager: manager, format: manager.displayFormat)
        
        if textView.string != newText {
            let shouldScroll = manager.autoScroll
            let wasAtBottom = context.coordinator.isScrolledToBottom()
            
            // 更新文本
            textView.string = newText
            
            #if DEBUG
            print("📝 updateNSView: 更新文本，新长度=\(newText.count)")
            #endif
            
            // 强制重新布局和显示
            textView.setNeedsDisplay(textView.visibleRect)
            
            // 自动滚动到底部
            if shouldScroll || wasAtBottom {
                DispatchQueue.main.async {
                    context.coordinator.scrollToBottom()
                }
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(manager: manager, scrollCoordinator: scrollCoordinator)
    }
    
    class Coordinator {
        weak var textView: NSTextView?
        weak var scrollView: NSScrollView?
        var manager: SerialPortManager
        weak var scrollCoordinator: ScrollCoordinator?
        var lastDataCount = 0
        var lastFormat: DisplayFormat = .text
        var cachedText = ""
        
        init(manager: SerialPortManager, scrollCoordinator: ScrollCoordinator) {
            self.manager = manager
            self.scrollCoordinator = scrollCoordinator
        }
        
        func getFormattedText(manager: SerialPortManager, format: DisplayFormat) -> String {
            let currentCount = manager.receivedData.count
            
            // 如果数据没变且格式没变，返回缓存
            if currentCount == lastDataCount && format == lastFormat {
                return cachedText
            }
            
            // 格式切换或首次加载：全量格式化
            if format != lastFormat || lastDataCount == 0 {
                let items = manager.receivedData.filter { $0.isReceived }
                cachedText = items.map { item in
                    manager.formatData(item.data, format: format)
                }.joined()
                
                lastDataCount = currentCount
                lastFormat = format
                return cachedText
            }
            
            // 增量更新：只格式化新数据
            if currentCount > lastDataCount {
                let newItems = Array(manager.receivedData[lastDataCount..<currentCount])
                let newText = newItems
                    .filter { $0.isReceived }
                    .map { item in
                        manager.formatData(item.data, format: format)
                    }
                    .joined()
                
                cachedText += newText
                lastDataCount = currentCount
                return cachedText
            }
            
            // 数据减少（清空）
            if currentCount < lastDataCount {
                let items = manager.receivedData.filter { $0.isReceived }
                cachedText = items.map { item in
                    manager.formatData(item.data, format: format)
                }.joined()
                
                lastDataCount = currentCount
                return cachedText
            }
            
            return cachedText
        }
        
        func isScrolledToBottom() -> Bool {
            guard let scrollView = scrollView else { return false }
            let contentView = scrollView.contentView
            let bounds = contentView.bounds
            let documentFrame = contentView.documentView?.frame ?? .zero
            
            return bounds.maxY >= documentFrame.maxY - 10
        }
        
        func scrollToBottom() {
            guard let textView = textView,
                  let timestampTextView = scrollCoordinator?.timestampScrollView?.documentView as? NSTextView else { return }
            
            // 确保两列都完成了布局
            textView.layoutManager?.ensureLayout(for: textView.textContainer!)
            timestampTextView.layoutManager?.ensureLayout(for: timestampTextView.textContainer!)
            
            // 使用setBoundsOrigin直接设置滚动位置，确保完全同步
            if let dataClipView = scrollView?.contentView,
               let timestampClipView = scrollCoordinator?.timestampScrollView?.contentView,
               let dataDocView = textView.enclosingScrollView?.documentView {
                
                // 计算底部位置
                let dataDocHeight = dataDocView.frame.height
                let dataVisibleHeight = dataClipView.bounds.height
                let maxY = max(0, dataDocHeight - dataVisibleHeight)
                
                // 同时设置两列的滚动位置
                var dataOrigin = dataClipView.bounds.origin
                dataOrigin.y = maxY
                dataClipView.setBoundsOrigin(dataOrigin)
                
                var timestampOrigin = timestampClipView.bounds.origin
                timestampOrigin.y = maxY
                timestampClipView.setBoundsOrigin(timestampOrigin)
            }
        }
    }
}
