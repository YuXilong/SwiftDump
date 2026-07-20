//
//  Log.swift
//  SwiftDump
//
//  Created by neilwu on 2020/6/26.
//  Copyright © 2020 nw. All rights reserved.
//

import Foundation

enum LogLevel: Int {
    case debug = 1
    //case info = 2
    case warn = 3
    case error = 4
}

private final class LogConfiguration: @unchecked Sendable {
    private let lock = NSLock()
    private var level: LogLevel = .warn

    func enableDebug() {
        lock.lock()
        level = .debug
        lock.unlock()
    }

    func shouldLog(_ level: LogLevel) -> Bool {
        lock.lock()
        let currentLevel = self.level
        lock.unlock()
        return level.rawValue >= currentLevel.rawValue
    }
}

fileprivate let logConfiguration = LogConfiguration()

func enableDebugLog() {
    logConfiguration.enableDebug()
}

func Log(_ msg: String, level: LogLevel = .debug, file: String = #file, method: String = #function, line: Int = #line) {

    if (!logConfiguration.shouldLog(level)) {
        return
    }

    var filename = file.components(separatedBy: "/").last ?? "unknowfile"
    filename = filename.components(separatedBy: ".").first ?? filename
    let methodPrefix: String = method.components(separatedBy: "(").first ?? method

    let str: String = "[\(filename) \(methodPrefix)] \(msg)"
    print(str)
}

func LogError(_ msg: String, file: String = #file, method: String = #function, line: Int = #line) {
    let prefix: String = "[error]"
    Log(prefix + msg, level: .error, file: file, method: method, line: line)
}

func LogWarn(_ msg: String, file: String = #file, method: String = #function, line: Int = #line) {
    let prefix: String = "[warn]"
    Log(prefix + msg, level: .warn, file: file, method: method, line: line)
}
