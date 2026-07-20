//
//  File.swift
//  SwiftDump
//
//  Created by neilwu on 2020/6/26.
//  Copyright © 2020 nw. All rights reserved.
//

import Foundation


// https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/include/swift/ABI/MetadataValues.h
enum SDContextDescriptorKind: UInt8, CustomStringConvertible {
    /// This context descriptor represents a module.
    case Module = 0

    /// This context descriptor represents an extension.
    case Extension = 1

    /// This context descriptor represents an anonymous possibly-generic context
    /// such as a function body.
    case Anonymous = 2

    /// This context descriptor represents a protocol context.
    case SwiftProtocol = 3

    /// This context descriptor represents an opaque type alias.
    case OpaqueType = 4

    /// First kind that represents a type of any sort.
    //case Type_First = 16

    /// This context descriptor represents a class.
    case Class = 16 // Type_First

    /// This context descriptor represents a struct.
    case Struct = 17 // Type_First + 1

    /// This context descriptor represents an enum.
    case Enum = 18 // Type_First + 2

    /// Last kind that represents a type of any sort.
    case Type_Last = 31

    case Unknow = 0xFF // It's not in swift source, this value only used for dump

    var description: String {
        switch self {
        case .Module: return "module";
        case .Extension: return "extension";
        case .Anonymous: return "anonymous";
        case .SwiftProtocol: return "protocol";
        case .OpaqueType: return "OpaqueType";
        case .Class: return "class";
        case .Struct: return "struct";
        case .Enum: return "enum";
        case .Type_Last: return "Type_Last";
        case .Unknow: return "unknow";
        }
    }
}

// Swift 6.3.3 ContextDescriptorFlags / TypeContextDescriptorFlags.
struct SDContextDescriptorFlags:CustomStringConvertible {
    let value: UInt32
    init(_ value: UInt32) {
        self.value = value;
    }

    /// The kind of context this descriptor describes.
    var kind: SDContextDescriptorKind {
        if let kind = SDContextDescriptorKind(rawValue: UInt8( value & 0x1F ) ) {
            return kind;
        }
        return SDContextDescriptorKind.Unknow;
    }

    /// Whether the context being described is generic.
    var isGeneric: Bool {
        return (value & 0x80) != 0;
    }

    /// Whether this is a unique record describing the referenced context.
    var isUnique: Bool {
        return (value & 0x40) != 0;
    }

    /// Whether invertible-protocol information trails this descriptor.
    var hasInvertibleProtocols: Bool {
        return (value & 0x20) != 0
    }

    /// Bits 8...15 are reserved by the current Swift ABI.
    var reservedFlags: UInt8 {
        return UInt8((value >> 8) & 0xFF);
    }

    /// The most significant two bytes of the flags word, which can have
    /// kind-specific meaning.
    var kindSpecificFlags: UInt16 {
        return UInt16((value >> 16) & 0xFFFF);
    }

    var typeFlags: SDTypeContextDescriptorFlags {
        return SDTypeContextDescriptorFlags(kindSpecificFlags)
    }

    var protocolFlags: SDProtocolContextDescriptorFlags {
        return SDProtocolContextDescriptorFlags(kindSpecificFlags)
    }

    var description: String {
        let kindDesc: String = kind.description;
        let kindSpecificFlagsStr: String = String(format: "0x%x", kindSpecificFlags);

        var desc: String = "<\(value.hex), \(kindDesc),";
        if isGeneric {
            desc += " isGeneric,"
        }
        if isUnique {
            desc += " isUnique,"
        } else {
            desc += " NotUnique,"
        }
        if hasInvertibleProtocols {
            desc += " hasInvertibleProtocols,"
        }

        if reservedFlags != 0 {
            desc += " reservedFlags \(reservedFlags),"
        }
        desc += " kindSpecificFlags \(kindSpecificFlagsStr)>";
        return desc;
    }
}

struct SDTypeContextDescriptorFlags {
    let value: UInt16

    init(_ value: UInt16) {
        self.value = value
    }

    var metadataInitializationKind: UInt16 { value & 0x3 }
    var hasImportInfo: Bool { (value & (1 << 2)) != 0 }
    var hasCanonicalMetadataPrespecializationsOrSingletonMetadataPointer: Bool {
        (value & (1 << 3)) != 0
    }
    var hasLayoutString: Bool { (value & (1 << 4)) != 0 }
    var classHasDefaultOverrideTable: Bool { (value & (1 << 6)) != 0 }
    var classIsActor: Bool { (value & (1 << 7)) != 0 }
    var classIsDefaultActor: Bool { (value & (1 << 8)) != 0 }
    var classResilientSuperclassReferenceKind: SDTypeReferenceKind? {
        SDTypeReferenceKind(rawValue: UInt8((value >> 9) & 0x7))
    }
    var classAreImmediateMembersNegative: Bool { (value & (1 << 12)) != 0 }
    var classHasResilientSuperclass: Bool { (value & (1 << 13)) != 0 }
    var classHasOverrideTable: Bool { (value & (1 << 14)) != 0 }
    var classHasVTable: Bool { (value & (1 << 15)) != 0 }
}

struct SDProtocolContextDescriptorFlags {
    let value: UInt16

    init(_ value: UInt16) {
        self.value = value
    }

    var isClassConstrained: Bool { (value & 0x1) == 0 }
    var isResilient: Bool { (value & (1 << 1)) != 0 }
    var specialProtocolKind: UInt8 { UInt8((value >> 2) & 0x3F) }
}

enum SDTypeReferenceKind: UInt8 {
    case directTypeDescriptor = 0
    case indirectTypeDescriptor = 1
    case directObjCClassName = 2
    case indirectObjCClass = 3
}

struct SDConformanceFlags {
    let value: UInt32

    init(_ value: UInt32) {
        self.value = value
    }

    var typeReferenceKind: SDTypeReferenceKind? {
        SDTypeReferenceKind(rawValue: UInt8((value >> 3) & 0x7))
    }
    var isRetroactive: Bool { (value & (1 << 6)) != 0 }
    var isSynthesizedNonUnique: Bool { (value & (1 << 7)) != 0 }
    var numConditionalRequirements: UInt8 { UInt8((value >> 8) & 0xFF) }
    var hasResilientWitnesses: Bool { (value & (1 << 16)) != 0 }
    var hasGenericWitnessTable: Bool { (value & (1 << 17)) != 0 }
    var isConformanceOfProtocol: Bool { (value & (1 << 18)) != 0 }
    var hasGlobalActorIsolation: Bool { (value & (1 << 19)) != 0 }
    var numConditionalPackDescriptors: UInt8 { UInt8((value >> 24) & 0xFF) }
}


enum SDFieldDescriptorKind: UInt16 {
    case `struct` = 0
    case `class` = 1
    case `enum` = 2
    case multiPayloadEnum = 3
    case `protocol` = 4
    case classProtocol = 5
    case objCProtocol = 6
    case objCClass = 7
    case unknown = 0xFFFF

    init(rawOrUnknown value: UInt16) {
        self = SDFieldDescriptorKind(rawValue: value) ?? .unknown
    }
}

struct SDFieldRecordFlags {
    let value: UInt32

    init(_ value: UInt32) {
        self.value = value
    }

    var isIndirectCase: Bool {
        return (value & 0x1) != 0
    }

    var isVar: Bool {
        return (value & 0x2) != 0
    }

    var isArtificial: Bool {
        return (value & 0x4) != 0
    }
}
