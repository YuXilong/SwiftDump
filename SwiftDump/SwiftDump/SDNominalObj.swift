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
    
    var namePtr: SDPointer = SDPointer(addr: 0)
    var typePtr: SDPointer = SDPointer(addr: 0)
}

enum SDCallableKind {
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
        return intent + "// Function at \(address.hex)\n" + intent + declaration + "\n"
    }
}

final class SDNominalObj {
    
    var typeName: String = ""; // type name
    var contextDescriptorFlag: SDContextDescriptorFlags = SDContextDescriptorFlags(0); // default
    var fields: [SDNominalObjField] = [];
    var callables: [SDCallableObj] = []
    
    var mangledTypeName: String = ""; // if someone else define this type as property, you can use this to retrive the name
    var nominalOffset: Int64 = 0; // Context Descriptor offset
    var accessorOffset: UInt64 = 0; // Access Function address
    
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
            str += intent + "// Access Function at \(accessorOffset.hex) \n";
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
                fs += "\(modifier) \(field.name): \(field.type);\n";
            }
            str += fs;
        }

        if !fields.isEmpty && !callables.isEmpty {
            str += "\n"
        }
        for callable in callables {
            str += callable.dumpDefine
        }
        
        str += "}\n";
        
        return str;
    }
    
}
