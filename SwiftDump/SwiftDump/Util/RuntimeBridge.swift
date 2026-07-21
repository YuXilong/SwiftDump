//
//  RuntimeBridge.swift
//  SwiftDump
//
//  Created by neilwu on 2020/6/26.
//  Copyright © 2020 nw. All rights reserved.
//

import Foundation


// size_t swift_demangle_getDemangledName(const char *MangledName, char *OutputBuffer,size_t Length)
@_silgen_name("swift_demangle_getDemangledName")
public func _getDemangledName(_ name:UnsafePointer<Int8>?, output:UnsafeMutablePointer<Int8>?, len:Int) -> Int;



// ex. So8UIButtonCSg -> UIButton?
// if demangle fail, will return the origin string
// Only demangle str start with So/$So/_$so/_T
func canDemangleFromRuntime(_ instr: String) -> Bool {
    return instr.hasPrefix("So")
        || instr.hasPrefix("$So")
        || instr.hasPrefix("_$So")
        || instr.hasPrefix("_T")
        || instr.hasPrefix("$s")
        || instr.hasPrefix("$S")
        || instr.hasPrefix("$e")
}

private func standardSwiftTypeAlias(_ typeName: String) -> String {
    switch typeName {
    case "Swift.Bool": return "Bool"
    case "Swift.Double": return "Double"
    case "Swift.Float": return "Float"
    case "Swift.Int": return "Int"
    case "Swift.Int8": return "Int8"
    case "Swift.Int16": return "Int16"
    case "Swift.Int32": return "Int32"
    case "Swift.Int64": return "Int64"
    case "Swift.String": return "String"
    case "Swift.UInt": return "UInt"
    case "Swift.UInt8": return "UInt8"
    case "Swift.UInt16": return "UInt16"
    case "Swift.UInt32": return "UInt32"
    case "Swift.UInt64": return "UInt64"
    case "Swift.Any": return "Any"
    default: return typeName
    }
}

private func normalizeDemangledTypeName(_ typeName: String) -> String {
    let cleaned = typeName
        .replacingOccurrences(of: "__C.", with: "")
        .replacingOccurrences(of: #"(?<![A-Za-z0-9_])Swift\."#,
                              with: "",
                              options: .regularExpression)
    return standardSwiftTypeAlias(fixOptionalTypeName(cleaned))
}

private func runtimeCopyDemangledName(_ mangledName: String) -> String? {
    let initialCapacity = max(256, mangledName.utf8.count * 4)
    return mangledName.withCString { ptr in
        var capacity = initialCapacity
        while capacity <= (1 << 20) {
            var buffer = [Int8](repeating: 0, count: capacity)
            let retLen = _getDemangledName(ptr, output: &buffer, len: capacity)
            if retLen > 0 && retLen < capacity {
                let bytes = buffer[0..<retLen].map { UInt8(bitPattern: $0) }
                return String(bytes: bytes, encoding: .utf8)
            }
            capacity *= 2
        }
        return nil
    }
}

func runtimeGetDemangledName(_ instr: String) -> String {
    var mangledName = instr
    if instr.hasPrefix("So") {
        mangledName = "$s" + instr
    } else if !(instr.hasPrefix("$s") || instr.hasPrefix("$S") || instr.hasPrefix("$e") || instr.hasPrefix("_T")) {
        return instr
    }
    
    guard let demangled = runtimeCopyDemangledName(mangledName) else {
        return instr
    }
    return normalizeDemangledTypeName(demangled)
}

/// Demangles a complete Swift linker symbol. Mach-O's string table prefixes
/// C-compatible symbols with an underscore, while the Swift runtime demangler
/// expects the mangling to begin with `$s`, `$S`, `$e`, or `_T`.
func runtimeGetDemangledSymbol(_ symbol: String) -> String? {
    var mangledName = symbol
    if mangledName.hasPrefix("_$") || mangledName.hasPrefix("__T") {
        mangledName.removeFirst()
    }
    guard canDemangleFromRuntime(mangledName),
          let demangled = runtimeCopyDemangledName(mangledName),
          demangled != mangledName else {
        return nil
    }
    return normalizeDemangledTypeName(demangled)
}

func getTypeFromMangledName(_ str: String) -> String {
    if str.isEmpty || str.hasPrefix("0x") {
        return str
    }
    if canDemangleFromRuntime(str) {
        let demangled = runtimeGetDemangledName(str)
        if demangled != str {
            return demangled
        }
    }
    if !str.isAsciiStr() {
        return str
    }
    
    let candidateNames: [String]
    if str.hasPrefix("$s") || str.hasPrefix("$S") || str.hasPrefix("$e") || str.hasPrefix("_T") {
        candidateNames = [str]
    } else {
        candidateNames = ["$s" + str]
    }
    
    for candidate in candidateNames {
        let demangled = runtimeGetDemangledName(candidate)
        if demangled != candidate {
            return demangled
        }
    }
    return str
}

// Optional<Any.Type>  => Any.Type?
// Optional<Int>  => Int?
func fixOptionalTypeName(_ typeName: String) -> String {
    let prefixes = ["Optional", "Swift.Optional"]
    guard let prefix = prefixes.first(where: { typeName.hasPrefix($0 + "<") }),
          typeName.hasSuffix(">") else {
        return typeName
    }
    var name: String = typeName.removingPrefix(prefix);
    name = name.removingPrefix("<")
    name = name.removingSuffix(">")
    if (name.contains(" ")) {
        return "(" + name + ")?"
    }
    return name + "?";
}

func removeSwiftModulePrefix(_ typeName: String) -> String {
    if let idx = typeName.firstIndex(of: ".") {
        let useIdx = typeName.index(after: idx)
        return String(typeName.suffix(from: useIdx ));
    }
    
    return typeName;
}
