//
//  NominalObj.swift
//  SwiftDump
//
//  Created by neilwu on 2020/6/26.
//  Copyright © 2020 nw. All rights reserved.
//

import Foundation


final class SDNominalObjField {
    var name: String = "";
    var type: String = "";
    var isVar: Bool = false
    var isIndirectCase: Bool = false
    var offset: SDFieldOffset = .unavailable
    
    var namePtr: SDPointer = SDPointer(addr: 0)
    var typePtr: SDPointer = SDPointer(addr: 0)
}

enum SDFieldOffset {
    case known(UInt64)
    case runtimeDependent
    case unavailable

    var dumpComment: String {
        switch self {
        case let .known(value): return value.hex
        case .runtimeDependent: return "runtime-dependent"
        case .unavailable: return "offset unavailable"
        }
    }
}

enum SDStaticPropertyValue {
    case literal(String)
    case runtimeInitialized
    case unavailable
}

struct SDStaticPropertyObj {
    let name: String
    let type: String
    let isVar: Bool
    let value: SDStaticPropertyValue

    var dumpDefine: String {
        let modifier = isVar ? "var" : "let"
        let declaration = "static \(modifier) \(name): \(type)"
        switch value {
        case let .literal(literal): return declaration + " = " + literal
        case .runtimeInitialized: return declaration + " // initialized at runtime"
        case .unavailable: return declaration + " // value unavailable offline"
        }
    }
}

enum SDCallableKind: Equatable {
    case method
    case initializer
    case deinitializer
    case getter
    case setter
    case readAccessor
    case modifyAccessor
}

struct SDCallableObj {
    let kind: SDCallableKind
    let name: String
    let declaration: String
    let address: UInt64

    var identity: String {
        declaration.removingPrefix("@objc ")
    }

    var dumpDefine: String {
        let intent = "    "
        if kind == .initializer {
            return intent + declaration + "\n"
        }
        return intent + "// Function at \(address.hex)\n" + intent + declaration + "\n"
    }
}

final class SDNominalObj {
    
    var typeName: String = ""; // type name
    var contextDescriptorFlag: SDContextDescriptorFlags = SDContextDescriptorFlags(0); // default
    var fields: [SDNominalObjField] = [];
    var staticProperties: [SDStaticPropertyObj] = []
    var callables: [SDCallableObj] = []
    
    var mangledTypeName: String = ""; // if someone else define this type as property, you can use this to retrive the name
    var nominalOffset: Int64 = 0; // Context Descriptor offset
    var accessorOffset: UInt64 = 0; // Access Function address
    var fieldOffsetVectorOffset: UInt32 = 0
    
    var protocols:[String] = [];
    var superClassName: String = "";
    
    var dumpDefine: String {
        let intent: String = "    ";
        var str: String = "";
        let kind = contextDescriptorFlag.kind;
        let declarationKind = kind == .Class && contextDescriptorFlag.typeFlags.classIsActor
            ? "actor"
            : kind.description
        str += "\(declarationKind) " + typeName;
        if (!superClassName.isEmpty) {
            str += " : " + superClassName;
        }
        if (protocols.count > 0) {
            let superStr: String = protocols.joined(separator: ",")
            let tmp: String = superClassName.isEmpty ? " : " : ",";
            str += tmp + superStr;
        }
        str += " {\n";
        
        str += intent + "// \(contextDescriptorFlag)\n";
        if (accessorOffset > 0) {
            str += intent + "// Access Function at \(accessorOffset.hex)\n";
        }
        for initializer in callables where initializer.kind == .initializer {
            str += intent + "// Init Function at \(initializer.address.hex)\n"
        }
        
        for field in fields {
            var fs: String = intent;
            if kind == .Enum {
                let casePrefix = field.isIndirectCase ? "indirect case " : "case "
                if (field.type.isEmpty) {
                    fs += "\(casePrefix)\(field.name)\n"; // without payload
                } else {
                    let tmp = field.type.hasPrefix("(") ? field.type : "(" + field.type + ")";
                    fs += "\(casePrefix)\(field.name)\(tmp)\n"; // enum with payload
                }
                
            } else {
                let modifier = field.isVar ? "var" : "let"
                fs += "\(modifier) \(field.name): \(field.type) // \(field.offset.dumpComment)\n";
            }
            str += fs;
        }

        for property in staticProperties {
            str += intent + property.dumpDefine + "\n"
        }

        if (!fields.isEmpty || !staticProperties.isEmpty) && !callables.isEmpty {
            str += "\n"
        }
        for callable in callables {
            str += callable.dumpDefine
        }
        
        str += "}\n";
        
        return str;
    }
    
}
