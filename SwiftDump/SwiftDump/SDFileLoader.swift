//
//  FileLoaderNew.swift
//  SwiftDump
//
//  Created by neilwu on 2020/6/26.
//  Copyright © 2020 nw. All rights reserved.
//

import Foundation

final class SDFileLoader {
    private let filePath: String;
    
    private(set) var machoFile: MachOFile? = nil;
    
    init(file: String) {
        self.filePath = file;
    }
    
    func load(cpu: MachOCpuType) -> Bool {
        
        Log("load file from \(self.filePath)")
        let fileURL = URL(fileURLWithPath: self.filePath);
        do {
            let fileObj = try MachOFile(url: fileURL, cpu: cpu);
            self.machoFile = fileObj;
            Log("load file success")
            return true;
        } catch {
            LogError("load fail, error \(error.localizedDescription)");
        }
        
        return false;
    }
    
    func getSegment(of seg: ESegment) -> MachOLoadCommand.Segment? {
        //return self.macho?.segments(withName: seg.rawValue).first?.value
        guard let machoFile = self.machoFile else {
            return nil;
        }
        for cmd in machoFile.commands {
            //seg.rawValue
            if let segment = cmd as? MachOLoadCommand.Segment {
                if (seg.rawValue == segment.name) {
                    return segment;
                }
            }
        }
        return nil;
    }
    
    func getSection(of section: ESection, seg: ESegment) -> Section64? {
        guard let segObj:MachOLoadCommand.Segment = self.getSegment(of: seg) else {
            return nil;
        }
        let ret = segObj.sections.first { (sect:Section64) -> Bool in
            return sect.sectname == section.rawValue;
        }
        return ret;
    }
    
    func readU32(_ archPtr: SDPointer) -> UInt32 {
        return self.machoFile?.readValue(at: archPtr) ?? 0;
    }
    
    func readU64(_ archPtr: SDPointer) -> UInt64 {
        return self.machoFile?.readValue(at: archPtr) ?? 0;
    }
    
    func readS32(_ archPtr: SDPointer) -> Int32 {
        return self.machoFile?.readValue(at: archPtr) ?? 0;
    }
    
    func resolveRelativePointer(_ ptr: SDPointer, clearingLowBits lowBitCount: Int = 0) -> SDPointer? {
        guard lowBitCount >= 0, lowBitCount < 31 else {
            return nil
        }
        let rawOffset = readS32(ptr)
        if rawOffset == 0 {
            return nil
        }
        let mask = Int32(bitPattern: ~((UInt32(1) << UInt32(lowBitCount)) - 1))
        return ptr.applying(relativeOffset: rawOffset & mask)
    }

    func resolveRelativeIndirectablePointer(_ ptr: SDPointer) -> SDPointer? {
        let rawOffset = readS32(ptr)
        guard rawOffset != 0 else {
            return nil
        }
        guard let relativeTarget = resolveRelativePointer(ptr, clearingLowBits: 1) else {
            return nil
        }
        if (rawOffset & 1) == 0 {
            return relativeTarget
        }
        return machoFile?.resolveStoredPointer(at: relativeTarget)
    }

    func resolveStoredPointer(at ptr: SDPointer) -> SDPointer? {
        return machoFile?.resolveStoredPointer(at: ptr)
    }

    func importedSymbol(at ptr: SDPointer) -> String? {
        return machoFile?.importedSymbol(at: ptr)
    }
    
    func readStr(_ ptr: SDPointer) -> String? {
        return self.machoFile?.readCString(at: ptr)
    }
    
}
