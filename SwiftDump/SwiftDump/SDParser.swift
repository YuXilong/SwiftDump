//
//  Parser.swift
//  SwiftDump
//
//  Created by neilwu on 2020/6/26.
//  Copyright © 2020 nw. All rights reserved.
//

import Foundation

final class SDParser {
    private(set) var protocolObjs:[SDProtocolObj] = [];
    private(set) var cacheProtocolAddressMap:[UInt64: String] = [:];

    private(set) var nominalObjs:[SDNominalObj] = [];
    private(set) var cacheNominalOffsetMap:[Int64: String] = [:]; // used for name demangle

    private(set) var nominalProtoMap:[String: [String] ] = [:];
    private(set) var classNameInheritanceMap: [String : String] = [:]; // [className : SuperClassName]

    private var loader: SDFileLoader? = nil;

    init(with loader: SDFileLoader) {
        self.loader = loader
    }

    // mangledName -> TypeName
    private var mangledNameMap:[String : String] = ["0x02f36d": "Int32",
        "0x02cd6d": "Int16", "0x027b6e": "UInt16",
        "0x022b6c": "UInt32",
        "0x02b98502": "Int64", "0x02418a02" : "UInt64",
        "0x02958802": "CGFloat"];

    func parseSwiftProto() {
        guard let loader = self.loader else {
            return;
        }
        let sectionType = ESection.swift5proto;
        Log("start parse section \(sectionType.rawValue)")
        guard let typeSect:Section64 = loader.getSection(of: sectionType, seg: ESegment.TEXT) else {
            Log("did not find section \(sectionType.rawValue)")
            return;
        }

        // This section contains an array of 32-bit signed integers. Each integer is a relative offset that points to a protocol conformance descriptor in the __TEXT.__const section.
        if (4 != typeSect.align) {
            Log("error! section \(sectionType.rawValue) is not 4 bytes align. align \(typeSect.align)")
            return;
        }
        /*
        type ProtocolConformanceDescriptor struct {
            ProtocolDescriptor    int32
            NominalTypeDescriptor int32
            ProtocolWitnessTable  int32
            ConformanceFlags      uint32
        }*/

        let num: Int = typeSect.num;
        let fileOffset: Int64 = Int64(typeSect.fileOffset);

        for i in 0..<num {
            let localOffset: Int = i * 4;
            let tmpPtr = SDPointer(addr: UInt64(fileOffset) + UInt64(localOffset) );
            guard let pcdPtr = loader.resolveRelativePointer(tmpPtr) else {
                continue
            }

            // https://github.com/apple/swift/blob/master/docs/ABI/TypeMetadata.rst#protocol-conformance-records
            var protoName: String = "";
            if let protocolPointer = loader.resolveRelativeIndirectablePointer(pcdPtr) {
                protoName = self.cacheProtocolAddressMap[protocolPointer.address] ?? ""
            }


            var nominalName: String = "";
            let nominalTypeDescriptorPtr = pcdPtr.add(4);
            let conformanceFlags = SDConformanceFlags(loader.readU32(pcdPtr.add(12)))
            switch conformanceFlags.typeReferenceKind {
            case .directTypeDescriptor:
                //A direct reference to a nominal type descriptor.
                if let ptr = loader.resolveRelativePointer(nominalTypeDescriptorPtr) {
                    nominalName = self.cacheNominalOffsetMap[Int64(ptr.address)] ?? ""
                    if nominalName.isEmpty, let str = loader.readStr(ptr) {
                        nominalName = str
                        self.cacheNominalOffsetMap[Int64(ptr.address)] = str
                    }
                }

            case .indirectTypeDescriptor:
                //An indirect reference to a nominal type descriptor.
                if let slot = loader.resolveRelativePointer(nominalTypeDescriptorPtr),
                   let ptr = loader.resolveStoredPointer(at: slot) {
                    nominalName = self.cacheNominalOffsetMap[Int64(ptr.address)] ?? ""
                }

            case .directObjCClassName:
                if let ptr = loader.resolveRelativePointer(nominalTypeDescriptorPtr) {
                    nominalName = loader.readStr(ptr) ?? ""
                }

            case .indirectObjCClass:
                //A reference to a pointer to an Objective-C class object.
                break

            case .none:
                break
            }

            if (!protoName.isEmpty && !nominalName.isEmpty) {
                // nominalProtoMap
                if nil != self.nominalProtoMap[nominalName] {
                    self.nominalProtoMap[nominalName]?.append(protoName)
                } else {
                    self.nominalProtoMap[nominalName] = [protoName];
                }
            }

            Log("\(i) \(pcdPtr.desc) proto=\(protoName), nominal=\(nominalName)");

        }
    }

    func parseSwiftProtos() {
        guard let loader = self.loader else {
            return;
        }
        let sectionType = ESection.swift5protos;
        Log("start parse section \(sectionType.rawValue)");

        guard let typeSect:Section64 = loader.getSection(of: sectionType, seg: ESegment.TEXT) else {
            Log("did not find section \(sectionType.rawValue)")
            return;
        }
        // This section contains an array of 32-bit signed integers. Each integer is a relative offset that points to a protocol descriptor in the __TEXT.__const section.
        if (4 != typeSect.align) {
            Log("error! section \(sectionType.rawValue) is not 4 bytes align. align \(typeSect.align)")
            return;
        }

        let num: Int = typeSect.num;
        let fileOffset: Int64 = Int64(typeSect.fileOffset);

        Log("section \(sectionType.rawValue) \(fileOffset.hex)")
        /*
        type ProtocolDescriptor struct {
            Flags                      uint32
            Parent                     int32
            Name                       int32
            NumRequirementsInSignature uint32
            NumRequirements            uint32
            AssociatedTypeNames        int32
            [The generic requirements that form the requirement signature]
            [The protocol requirements of the protocol]
        }*/
        for i in 0..<num {
            let tmp: Int = i * 4;
            let tmpPtr = SDPointer(addr: UInt64(tmp) + UInt64(fileOffset) );
            guard let pdPtr = loader.resolveRelativePointer(tmpPtr) else {
                continue
            }

            // 1. flags
            let flags:UInt32 = loader.readU32(pdPtr);
            // 3. name
            guard let namePtr = loader.resolveRelativePointer(pdPtr.add(8)) else {
                continue
            }
            guard let nameStr: String = loader.readStr(namePtr) else {
                continue;
            }

            let numRequirementsInSignature:UInt32 = loader.readU32(pdPtr.add(4 * 3));
            let numRequirements:UInt32 = loader.readU32(pdPtr.add(4 * 4));

            let associatedTypeNamesOffset:Int32 = loader.readS32(pdPtr.add(4 * 5));

            let obj = SDProtocolObj();
            obj.flags = flags;
            obj.name = nameStr;
            obj.numRequirementsInSignature = numRequirementsInSignature;
            obj.numRequirements = numRequirements;
            obj.descriptorOffset = pdPtr.address

            self.cacheProtocolAddressMap[pdPtr.address] = nameStr;

            Log("\(i) \(pdPtr.desc) flags \(flags.hex), \(nameStr), numRequirementsInSignature \(numRequirementsInSignature.hex), numRequirements \(numRequirements.hex) associatedTypeNames \(associatedTypeNamesOffset) \(associatedTypeNamesOffset.hex)")
            if (associatedTypeNamesOffset != 0) {
                let associatedTypeNamesPtr = pdPtr.add(4 * 5 + Int64(associatedTypeNamesOffset));
                let associatedTypeNames = loader.readStr(associatedTypeNamesPtr) ?? ""
                obj.associatedTypeNames = associatedTypeNames;
            }

            self.protocolObjs.append(obj)
        }

        for obj in self.protocolObjs {
            let requirementBase = SDPointer(addr: obj.descriptorOffset).add(24)
            let requirementCount = min(Int(obj.numRequirementsInSignature), 10_000)
            for index in 0..<requirementCount {
                let requirement = requirementBase.add(Int64(index * 12))
                let requirementFlags = loader.readU32(requirement)
                guard (requirementFlags & 0x1F) == 0,
                      let protocolPointer = loader.resolveRelativeIndirectablePointer(requirement.add(8)),
                      let inheritedName = cacheProtocolAddressMap[protocolPointer.address],
                      inheritedName != obj.name,
                      !obj.superProtocols.contains(inheritedName) else {
                    continue
                }
                obj.superProtocols.append(inheritedName)
            }
        }

    }

    func parseSwiftType() {
        guard let loader = self.loader else {
            return;
        }
        let sectionType = ESection.swift5types;
        Log("start parse \(sectionType.rawValue)")

        guard let typeSect:Section64 = loader.getSection(of: sectionType, seg: ESegment.TEXT) else {
            Log("did find section \(ESection.swift5types.rawValue), may be the binary does not contain swift5 lib?")
            return;
        }

        //print("addr", String(format: "0x%llx", typeSect.fileOffset))

        // __swift5_types is 4 bytes align, equal to typeSect.align
        if (4 != typeSect.align) {
            Log("error! section \(sectionType.rawValue) is not 4 bytes align. align \(typeSect.align)")
            return;
        }

        let num: Int = typeSect.num;

        // mk_vm_address_t is uint64_t
        let fileOffset: Int64 = Int64(typeSect.fileOffset);

        for i in 0..<num {
            let localOffset: Int = i * 4;
            //let nominalLocalOffset:Int32 = data.readS32(offset: localOffset); // may be negative value

            let tmpPtr = SDPointer(addr: UInt64(fileOffset) + UInt64(localOffset) );
            let nominalLocalOffset = loader.readS32(tmpPtr)
            guard let nominalPtr = loader.resolveRelativePointer(tmpPtr),
                  let nominalArchOffset = Int64(exactly: nominalPtr.address) else {
                continue
            }

            // 1. flags
            let flags:UInt32 = loader.readU32(nominalPtr);
            let sdfObj = SDContextDescriptorFlags(flags);

            // 2. parent context relative pointer (logged for ABI diagnostics)
            let parentVal = loader.readS32(nominalPtr.add(4))

            // 3. name
            guard let namePtr = loader.resolveRelativePointer(nominalPtr.add(8)) else {
                continue
            }
            guard let nameStr: String = loader.readStr(namePtr) else {
                continue;
            }
            // 4. AccessFunction. // Access functions will always return the correct metadata record;
            let accessorPtr = loader.resolveRelativePointer(nominalPtr.add(12))

            #if DEBUG

            #endif

            let obj: SDNominalObj = SDNominalObj();
            obj.typeName = nameStr;
            obj.contextDescriptorFlag = sdfObj;
            obj.nominalOffset = nominalArchOffset;
            obj.accessorOffset = accessorPtr?.address ?? 0;
            self.nominalObjs.append(obj);

            if (sdfObj.kind == .Class) {
                obj.superClassName = resolveSuperClassName(nominalPtr);
            } else if (sdfObj.kind == .Enum) {
                //let numPayloadCasesAndPayloadSizeOffset:UInt32 = loader.readU32(nominalPtr.add(4 * 5));
                //let numEmptyCases:UInt32 = loader.readU32(nominalPtr.add(4 * 6));
                //print("\(i)  ", "numPayloadCasesAndPayloadSizeOffset \(numPayloadCasesAndPayloadSizeOffset), numEmptyCases \(numEmptyCases)");
            } else if (sdfObj.kind == .Struct) {
                //let numFields:UInt32 = loader.readU32(nominalPtr.add(4 * 5));
                //let fieldOffsetVectorOffset:UInt32 = loader.readU32(nominalPtr.add(4 * 6));
                //print("\(i)  ", "numFields \(numFields), fieldOffsetVectorOffset \(fieldOffsetVectorOffset)");
            }

            self.cacheNominalOffsetMap[nominalArchOffset] = nameStr;

            // in swift5_filedmd
            if let fieldDescriptorPtr = loader.resolveRelativePointer(nominalPtr.add(4 * 4)) {
                if let mangledTypeNamePtr = loader.resolveRelativePointer(fieldDescriptorPtr),
                   let mangledTypeName = readMangledName(at: mangledTypeNamePtr) {
                    obj.mangledTypeName = mangledTypeName
                }
                dumpFieldDescriptor(loader: loader, fieldDescriptorPtr: fieldDescriptorPtr, to: obj)
            }

            Log("\(i). nominalLocalOffset \(nominalLocalOffset ), nominalArchOffset \(nominalArchOffset.hex ), flags \(flags.hex)=\(sdfObj.kind), parent \(parentVal.hex), namePtr \(namePtr.desc) \(nameStr), mangledTypeName \(obj.mangledTypeName)");

            if (obj.mangledTypeName.count > 0) {
                mangledNameMap[obj.mangledTypeName] = obj.typeName;
            }
        }
    }

    private func resolveSuperClassName(_ nominalPtr: SDPointer) -> String {
        //nominalPtr
        let ptr = nominalPtr.add(4 * 5)
        let superClassTypeVal = self.loader?.readS32(ptr) ?? 0;
        if (superClassTypeVal == 0) {
            return "";
        }

        var retName: String = "";

        let superClassRefPtr = ptr.add( Int64(superClassTypeVal) );
        if let superRefStr = self.readMangledName(at: superClassRefPtr), !superRefStr.isEmpty {
            if superRefStr.hasPrefix("0x") {
                retName = self.mangledNameMap[superRefStr] ?? superRefStr;
            } else {
                retName = superRefStr; // resolve later
            }
        }
        return retName;
    }

    private func getISAClassName(of obj:SDObjCClass) -> String {
        if (obj.isaAddress == 0) {
            return "";
        }

        let dataSlice: Data? = self.loader?.machoFile?.dataSlice;

        guard let metaObj:SDObjCClass = dataSlice?.extract(SDObjCClass.self, offset: Int(obj.isaAddress & 0xFFFFFFFF)) else {
            return "";
        }
        if (metaObj.dataAddr == 0) {
            return "";
        }
        // find class name string
        guard let dataObj:SDObjCClassROData = dataSlice?.extract(SDObjCClassROData.self, offset: Int(metaObj.dataAddr & 0xFFFFFFFF)) else {
            return "";
        }

        let name: String = self.loader?.readStr(SDPointer(addr: dataObj.nameAddr & 0xFFFFFFFF)) ?? "";
        //print("  metaname:", dataObj.nameAddr.hex, name)
        return name;
    }

    private func getSuperClassName(of obj:SDObjCClass) -> String {
        if (obj.superclassAddress == 0) {
            return "";
        }
        let dataSlice: Data? = self.loader?.machoFile?.dataSlice;

        guard let superClassObj:SDObjCClass = dataSlice?.extract(SDObjCClass.self, offset: Int(obj.superclassAddress & 0xFFFFFFFF)) else {
            return "";
        }

        if (superClassObj.isaAddress == 0) {
            // find class name string
            if let dataObj:SDObjCClassROData = dataSlice?.extract(SDObjCClassROData.self, offset: Int(superClassObj.dataAddr & 0xFFFFFFFF)) {
                //
                let name: String = self.loader?.readStr(SDPointer(addr: dataObj.nameAddr & 0xFFFFFFFF)) ?? "";
                //print("    super dataObj:", dataObj.nameAddr.hex, name)
                return name;
            }
        } else {
            return getISAClassName(of: superClassObj);
        }

        return "";
    }
    private func demangleClassName(_ name: String) -> String {
        var tmp: String = runtimeGetDemangledName(name);
        tmp = removeSwiftModulePrefix(tmp)
        return tmp;
    }

    func parseSwiftOCClass() {
        guard let loader = self.loader else {
            return;
        }
        Log("start parse section \(ESection.objc_classlist.rawValue)")
        let typeSect:Section64
        if let tmp:Section64 = loader.getSection(of: ESection.objc_classlist, seg: ESegment.DATA) {
            typeSect = tmp;
            Log("use seg \(ESegment.DATA.rawValue)");
        } else if let tmp:Section64 = loader.getSection(of: ESection.objc_classlist, seg: ESegment.DATA_CONST) {
            typeSect = tmp;
            Log("use seg \(ESegment.DATA_CONST.rawValue)");
        } else {
            LogWarn("didn't find section \(ESection.objc_classlist.rawValue)")
            return;
        }

        let fileOffset: UInt64 = UInt64(typeSect.fileOffset);

        var metaClassNameMap:[UInt64: String] = [:]; // isaAddress : name

        // align is 8
        for i in 0..<typeSect.num {
            let tmpOffset: UInt64 = UInt64(i) * UInt64(typeSect.align);
            var valAddress:UInt64 = loader.readU64(SDPointer(addr: fileOffset + tmpOffset ) );
            valAddress = valAddress & 0xFFFFFFFF;

            guard let obj:SDObjCClass = loader.machoFile?.dataSlice.extract(SDObjCClass.self, offset: Int(valAddress)) else {
                continue;
            }
            //print(obj)

            let metaClassName: String = demangleClassName(self.getISAClassName(of: obj));
            if (metaClassName.count > 0) {
                metaClassNameMap[obj.isaAddress] = metaClassName;
            } else {
                continue;
            }

            let superClassName: String = demangleClassName(self.getSuperClassName(of: obj) );
            if !superClassName.isEmpty && !superClassName.hasPrefix("0x") {
                Log("\(i). \(metaClassName) : \(superClassName)")
                self.classNameInheritanceMap[metaClassName] = superClassName;
            } else {
                Log("\(i). \(metaClassName)")
            }
        }

    }


    func dumpAll() {

        for obj in self.protocolObjs {
            let protoName: String = obj.name;
            if let arr:[String] = self.nominalProtoMap[protoName] {
                for inheritedName in arr where !obj.superProtocols.contains(inheritedName) {
                    obj.superProtocols.append(inheritedName)
                }
            }
            print(obj.dumpDefine)
        }

        for obj in nominalObjs {

            if let arr:[String] = self.nominalProtoMap[obj.typeName] {
                obj.protocols = arr;
            }

            var resoleSuperFromOC:Bool = obj.superClassName.isEmpty;
            if (obj.superClassName.hasPrefix("0x")) {
                if let tmp = self.mangledNameMap[obj.superClassName], !tmp.isEmpty {
                    obj.superClassName = tmp;
                    resoleSuperFromOC = false;
                }
            } else {
                let tmp = runtimeGetDemangledName("$s" + obj.superClassName);
                if (!tmp.hasPrefix("$s") && tmp != obj.superClassName) {
                    obj.superClassName = tmp;
                }
            }
            if (resoleSuperFromOC) {
                obj.superClassName = self.classNameInheritanceMap[obj.typeName] ?? obj.superClassName;
            }


            for field in obj.fields {
                let ft: String = field.type;
                if (ft.hasPrefix("0x")) {
                if let fixName = mangledNameMap[ft] {
                    field.type = fixName;
                } else {
                    field.type = fixMangledName(ft, startPtr: field.typePtr)
                }

                } else if (ft != "String") {
                    let tmp = getTypeFromMangledName(ft)
                    if (tmp != ft) {
                        field.type = tmp
                    }
                }
            }
            print(obj.dumpDefine)
        }
    }

    private func isPrintableMangledASCII(_ bytes: [UInt8]) -> Bool {
        guard let str = String(bytes: bytes, encoding: .ascii) else {
            return false
        }
        return str.isAsciiStr()
    }

    private func symbolicPayloadLength(for byte: UInt8) -> Int {
        if (0x01...0x17).contains(byte) {
            return 4
        }
        if (0x18...0x1F).contains(byte) {
            return 8
        }
        return 0
    }

    private func readMangledNameBytes(at ptr: SDPointer, maxLength: Int = 0x4000) -> [UInt8]? {
        guard let machoFile = self.loader?.machoFile,
              let startOffset = machoFile.dataOffset(for: ptr) else {
            return nil
        }
        let data = machoFile.dataSlice
        var offset = startOffset
        guard data.hasReadableRange(offset: offset, length: 1) else {
            return nil
        }

        var result: [UInt8] = []
        while data.hasReadableRange(offset: offset, length: 1) && result.count < maxLength {
            let current = data.readU8(offset: offset)
            offset += 1
            if current == 0 {
                return result
            }
            if current == 0xFF {
                continue
            }

            result.append(current)
            let payloadLength = symbolicPayloadLength(for: current)
            if payloadLength > 0 {
                guard data.hasReadableRange(offset: offset, length: payloadLength) else {
                    return nil
                }
                for payloadOffset in 0..<payloadLength {
                    result.append(data.readU8(offset: offset + payloadOffset))
                }
                offset += payloadLength
            }
        }

        return nil
    }

    private func readMangledName(at ptr: SDPointer) -> String? {
        guard let bytes = readMangledNameBytes(at: ptr), !bytes.isEmpty else {
            return self.loader?.readStr(ptr)
        }
        if isPrintableMangledASCII(bytes) {
            return String(bytes: bytes, encoding: .ascii)
        }
        return "0x" + bytes.hex
    }

    private func decodeMangledType(at ptr: SDPointer) -> String? {
        guard let bytes = readMangledNameBytes(at: ptr), !bytes.isEmpty else {
            return nil
        }
        return decodeMangledType(bytes: bytes, startPtr: ptr)
    }

    private func decodeMangledType(bytes: [UInt8], startPtr: SDPointer) -> String {
        if isPrintableMangledASCII(bytes), let mangledName = String(bytes: bytes, encoding: .ascii) {
            let demangled = getTypeFromMangledName(mangledName)
            if demangled != mangledName {
                return demangled
            }
        }
        return fixMangledName("0x" + bytes.hex, startPtr: startPtr)
    }

    private func dumpFieldDescriptor(loader: SDFileLoader, fieldDescriptorPtr: SDPointer, to: SDNominalObj) {
        guard let machoFile = loader.machoFile,
              let fieldDescriptorOffset = machoFile.dataOffset(for: fieldDescriptorPtr, size: 16) else {
            return
        }
        let data = machoFile.dataSlice

        let fieldDescriptorKind = SDFieldDescriptorKind(rawOrUnknown: UInt16(bitPattern: data.readS16(offset: fieldDescriptorOffset + 8)))
        let fieldRecordSize = Int(UInt16(bitPattern: data.readS16(offset: fieldDescriptorOffset + 10)))
        let numFields = loader.readU32(fieldDescriptorPtr.add(12))

        if (0 == numFields) {
            return;
        }
        if (numFields >= 1000 || fieldRecordSize < 12) {
            Log("[dumpFieldDescriptor] ignore \(to.typeName), numFields \(numFields), fieldRecordSize \(fieldRecordSize), kind \(fieldDescriptorKind)")
            return
        }

        let fieldStart: SDPointer = fieldDescriptorPtr.add(16)
        for i in 0..<Int64(numFields) {
            let fieldAddr = fieldStart.add(i * Int64(fieldRecordSize))
            guard machoFile.dataOffset(for: fieldAddr, size: fieldRecordSize) != nil else {
                break
            }

            let recordFlags = SDFieldRecordFlags(loader.readU32(fieldAddr))
            if recordFlags.isArtificial {
                continue
            }

            let fieldNameRel = loader.readS32(fieldAddr.add(8))
            let fieldNamePtr = fieldAddr.add(8).add(Int64(fieldNameRel))
            guard let fieldName = loader.readStr(fieldNamePtr), !fieldName.isEmpty, fieldName.count <= 100 else {
                continue
            }

            let typeNameRel = loader.readS32(fieldAddr.add(4))
            let typeNamePtr = fieldAddr.add(4).add(Int64(typeNameRel))

            let fieldObj = SDNominalObjField()
            fieldObj.name = fieldName
            fieldObj.namePtr = fieldNamePtr
            fieldObj.typePtr = typeNamePtr
            fieldObj.isVar = recordFlags.isVar
            fieldObj.isIndirectCase = recordFlags.isIndirectCase

            if typeNameRel != 0 {
                fieldObj.type = decodeMangledType(at: typeNamePtr) ?? ""
            } else if fieldDescriptorKind != .enum && to.contextDescriptorFlag.kind != .Enum {
                continue
            }
            to.fields.append(fieldObj)
        }
    }

    func makeDemangledTypeName(_ type: String, header: String) -> String {

        let isArray:Bool = header.contains("Say") || header.contains("SDy");
        let suffix: String = isArray ? "G" : "";
        let fixName = "So\(type.count)\(type)C" + suffix;
        return fixName;
    }

    private func signedRelativeOffset(from bytes: [UInt8]) -> Int32? {
        guard bytes.count == 4 else {
            return nil
        }
        let raw = UInt32(bytes[0])
            | (UInt32(bytes[1]) << 8)
            | (UInt32(bytes[2]) << 16)
            | (UInt32(bytes[3]) << 24)
        return Int32(bitPattern: raw)
    }

    private func descriptorName(fromImportedSymbol symbol: String) -> String? {
        var mangled = symbol
        if mangled.hasPrefix("_") {
            mangled.removeFirst()
        }
        guard mangled.hasPrefix("$s") || mangled.hasPrefix("$S") || mangled.hasPrefix("$e") else {
            return nil
        }

        if mangled.hasSuffix("Mp") {
            mangled = String(mangled.dropLast(2)) + "P"
        }
        let demangled = runtimeGetDemangledName(mangled)
        let prefixes = [
            "protocol descriptor for ",
            "nominal type descriptor for ",
            "type metadata for "
        ]
        for prefix in prefixes where demangled.hasPrefix(prefix) {
            return String(demangled.dropFirst(prefix.count))
        }
        return demangled == mangled ? nil : demangled
    }

    func fixMangledName(_ name: String, startPtr: SDPointer) -> String {
        // symbolic-references
        let hexName: String = name.removingPrefix("0x")
        let dataArray: [UInt8] = hexName.hexBytes
        //print(dataArray.map{ String(format: "0x%x", $0) })

        var mangledName: String = "";
        var i: Int = 0;

        while i < dataArray.count {
            let val = dataArray[i];
            if (val == 0xFF) {
                i += 1
                continue
            }

            let payloadLength = symbolicPayloadLength(for: val)
            if (val == 0x01 && payloadLength > 0) {
                //find
                let fromIdx:Int = i + 1; // ignore 0x01
                let toIdx:Int = fromIdx + payloadLength
                if (toIdx > dataArray.count) {
                    mangledName = mangledName + String(format: "%c", val);
                    i = i + 1;
                    continue;
                }
                let offsetArray:[UInt8] = Array(dataArray[fromIdx..<toIdx]);

                let result: String = resoleSymbolicRefDirectly(offsetArray, ptr: startPtr.add( Int64(fromIdx) ));
                if (i == 0 && toIdx >= dataArray.count) {
                    mangledName = mangledName + result; // use original result
                } else {
                    let fixName = makeDemangledTypeName(result, header: "")
                    mangledName = mangledName + fixName;
                }

                i = toIdx;
            } else if (val == 0x02 && payloadLength > 0) {
                //indirectly
                let fromIdx:Int = i + 1; // ignore 0x02
                let toIdx:Int = fromIdx + payloadLength
                if (toIdx > dataArray.count) {
                    return name
                }

                let offsetArray:[UInt8] = Array(dataArray[fromIdx..<toIdx]);
                let result: String = resoleSymbolicRefIndirectly(offsetArray, ptr: startPtr.add( Int64(fromIdx) ));

                if i == 0 && !result.hasPrefix("0x") {
                    let remaining = Array(dataArray[toIdx...])
                    if remaining == [0x5F, 0x70] {
                        return result
                    }
                    if remaining == [0x58, 0x70] || remaining == [0x5F, 0x70, 0x58, 0x70] {
                        return result + ".Type"
                    }
                }

                if (i == 0 && toIdx >= dataArray.count) {
                    mangledName = mangledName + result;
                } else {
                    let fixName = makeDemangledTypeName(result, header: mangledName)
                    mangledName = mangledName + fixName
                }
                i = toIdx
            } else if payloadLength > 0 {
                return name
            } else {
                //check next
                mangledName = mangledName + String(format: "%c", val);
                i = i + 1;
            }
        }

        let result: String = getTypeFromMangledName(mangledName)
        if (result == mangledName) {
            let tmp: String = runtimeGetDemangledName("$s" + mangledName)
            if (tmp != ("$s" + mangledName)) {
                return tmp;
            }
        }
        return result;
    }

    func resoleSymbolicRefDirectly(_ hexArray: [UInt8], ptr: SDPointer) -> String {
        // {any-generic-type, protocol, opaque-type-decl-name} ::= '\x01' .{4} // Reference points directly to context descriptor
        let origHex: String = "0x01" + hexArray.hex;
        guard let offset = signedRelativeOffset(from: hexArray) else {
            return origHex;
        }

        let descriptorPointer = ptr.applying(relativeOffset: offset)
        if let nominalName = cacheNominalOffsetMap[Int64(descriptorPointer.address)] {
            return nominalName
        }
        return cacheProtocolAddressMap[descriptorPointer.address] ?? origHex
    }

    func resoleSymbolicRefIndirectly(_ hexArray: [UInt8], ptr: SDPointer) -> String {
        // {any-generic-type, protocol, opaque-type-decl-name} ::= '\x02' .{4} // Reference points indirectly to context descriptor
        let origHex: String = "0x02" + hexArray.hex;
        guard let offset = signedRelativeOffset(from: hexArray),
              let loader = self.loader else {
            return origHex;
        }

        let pointerSlot = ptr.applying(relativeOffset: offset)
        if let symbol = loader.importedSymbol(at: pointerSlot),
           let name = descriptorName(fromImportedSymbol: symbol) {
            return name
        }
        if let descriptorPointer = loader.resolveStoredPointer(at: pointerSlot) {
            if let nominalName = cacheNominalOffsetMap[Int64(descriptorPointer.address)] {
                return nominalName
            }
            if let protocolName = cacheProtocolAddressMap[descriptorPointer.address] {
                return protocolName
            }
        }
        return origHex
    }
}
