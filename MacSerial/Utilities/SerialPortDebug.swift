//
//  SerialPortDebug.swift
//  MacSerial
//
//  Created by Tomosawa on 2025/12/19.
//

import Foundation
import IOKit
import IOKit.serial

class SerialPortDebug {
    static func printAvailablePorts() {
        print("=== 扫描可用串口 ===")
        
        let matchingDict = IOServiceMatching(kIOSerialBSDServiceValue)
        var iterator: io_iterator_t = 0
        
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matchingDict, &iterator)
        if result == KERN_SUCCESS {
            defer { IOObjectRelease(iterator) }
            
            var serialService = IOIteratorNext(iterator)
            var count = 0
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
                    count += 1
                    print("\(count). \(devicePath)")
                    
                    // 检查文件是否存在
                    let fileExists = FileManager.default.fileExists(atPath: devicePath)
                    print("   文件存在: \(fileExists)")
                    
                    // 检查权限
                    if fileExists {
                        let attributes = try? FileManager.default.attributesOfItem(atPath: devicePath)
                        print("   权限: \(attributes?[.posixPermissions] ?? "未知")")
                    }
                }
            }
            
            if count == 0 {
                print("未找到任何串口设备")
            }
        } else {
            print("IOServiceGetMatchingServices 失败")
        }
        
        print("==================")
    }
    
    static func testOpenPort(_ portPath: String) {
        print("\n=== 测试打开串口: \(portPath) ===")
        
        // 检查文件是否存在
        if !FileManager.default.fileExists(atPath: portPath) {
            print("错误: 串口文件不存在")
            return
        }
        
        print("尝试打开串口...")
        let fd = open(portPath, O_RDWR | O_NOCTTY)
        
        if fd == -1 {
            let error = String(cString: strerror(errno))
            print("打开失败: \(error) (errno: \(errno))")
            
            switch errno {
            case EACCES:
                print("提示: 权限不足，可能需要 sudo 或添加用户到 dialout/uucp 组")
            case ENOENT:
                print("提示: 设备不存在")
            case EBUSY:
                print("提示: 设备正在被其他程序使用")
            default:
                break
            }
        } else {
            print("成功打开! 文件描述符: \(fd)")
            close(fd)
            print("已关闭串口")
        }
        
        print("==================\n")
    }
}
