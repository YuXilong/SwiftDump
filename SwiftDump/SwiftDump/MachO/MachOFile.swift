/*
 Copyright Geoffrey Foster
 
 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at
 
 http://www.apache.org/licenses/LICENSE-2.0
 
 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
 */
//
//  MachO.swift
//  Machismo
//
//  Created by Geoffrey Foster on 2018-05-12.
//  Copyright © 2018 g-Off.net. All rights reserved.
//
//  neilwu modify this file for SwiftDump

import Foundation

enum MachOFileError: Error {
    case archFail
    case invalidMachO
    case truncated
}

public enum MachOCpuType:String, CaseIterable {
    case x86_64 = "x86_64"
    case arm64 = "arm64"
    
    var cputype:cpu_type_t {
        switch self {
        case .x86_64: return CPU_TYPE_X86_64;
        case .arm64: return CPU_TYPE_ARM64;
        }
    }
}

fileprivate struct MachAttributes {
    let magic: UInt32
    let is64Bit: Bool
    let isByteSwapped: Bool
}

private struct MachOChainedFixups {
    private struct SegmentFormat {
        let fileRange: Range<UInt64>
        let pointerFormat: UInt16
    }

    enum Resolution {
        case fileOffset(UInt64)
        case importSymbol(String)
    }

    private let imageBaseAddress: UInt64
    private let segmentFormats: [SegmentFormat]
    private let importedSymbols: [String]

    init?(data: Data,
          payloadOffset: Int,
          payloadSize: Int,
          segments: [MachOLoadCommand.Segment]) {
        guard payloadSize >= 28,
              data.hasReadableRange(offset: payloadOffset, length: payloadSize),
              let startsOffset: UInt32 = data.readValue(payloadOffset + 4),
              let importsOffset: UInt32 = data.readValue(payloadOffset + 8),
              let symbolsOffset: UInt32 = data.readValue(payloadOffset + 12),
              let importsCount: UInt32 = data.readValue(payloadOffset + 16),
              let importsFormat: UInt32 = data.readValue(payloadOffset + 20),
              let symbolsFormat: UInt32 = data.readValue(payloadOffset + 24),
              symbolsFormat == 0,
              importsCount <= 1_000_000 else {
            return nil
        }

        let payloadEnd = payloadOffset + payloadSize
        let startsBase = payloadOffset + Int(startsOffset)
        let importsBase = payloadOffset + Int(importsOffset)
        let symbolsBase = payloadOffset + Int(symbolsOffset)
        guard startsBase >= payloadOffset,
              importsBase >= payloadOffset,
              symbolsBase >= payloadOffset,
              startsBase < payloadEnd,
              importsBase <= payloadEnd,
              symbolsBase <= payloadEnd,
              let segmentCount: UInt32 = data.readValue(startsBase),
              segmentCount <= 4_096 else {
            return nil
        }

        var formats: [SegmentFormat] = []
        let usableSegmentCount = min(Int(segmentCount), segments.count)
        for segmentIndex in 0..<usableSegmentCount {
            let entryOffset = startsBase + 4 + segmentIndex * 4
            guard entryOffset <= payloadEnd - 4,
                  let relativeInfoOffset: UInt32 = data.readValue(entryOffset) else {
                return nil
            }
            if relativeInfoOffset == 0 {
                continue
            }

            let infoOffset = startsBase + Int(relativeInfoOffset)
            guard infoOffset >= startsBase,
                  infoOffset < payloadEnd,
                  let infoSize: UInt32 = data.readValue(infoOffset),
                  infoSize >= 22,
                  Int(infoSize) <= payloadEnd - infoOffset,
                  data.hasReadableRange(offset: infoOffset, length: Int(infoSize)),
                  let pointerFormat: UInt16 = data.readValue(infoOffset + 6) else {
                return nil
            }

            let segment = segments[segmentIndex]
            let rangeEnd = segment.fileoff &+ segment.filesize
            guard rangeEnd >= segment.fileoff else {
                return nil
            }
            formats.append(SegmentFormat(fileRange: segment.fileoff..<rangeEnd,
                                         pointerFormat: pointerFormat))
        }

        let importStride: Int
        switch importsFormat {
        case 1: importStride = 4
        case 2: importStride = 8
        case 3: importStride = 16
        default: return nil
        }

        var symbols: [String] = []
        symbols.reserveCapacity(Int(importsCount))
        for index in 0..<Int(importsCount) {
            let entryOffset = importsBase + index * importStride
            guard entryOffset >= importsBase,
                  entryOffset <= payloadEnd - importStride else {
                return nil
            }
            let nameOffset: UInt32
            switch importsFormat {
            case 1, 2:
                guard let raw: UInt32 = data.readValue(entryOffset) else {
                    return nil
                }
                nameOffset = raw >> 9
            case 3:
                guard let raw: UInt64 = data.readValue(entryOffset) else {
                    return nil
                }
                nameOffset = UInt32(truncatingIfNeeded: raw >> 32)
            default:
                return nil
            }

            let symbolOffset = symbolsBase + Int(nameOffset)
            guard symbolOffset >= symbolsBase,
                  symbolOffset < payloadEnd,
                  let symbol = data.readCString(from: symbolOffset,
                                                maxLength: payloadEnd - symbolOffset) else {
                return nil
            }
            symbols.append(symbol)
        }

        guard let imageBase = segments
            .filter({ $0.filesize > 0 && $0.vmaddr >= $0.fileoff })
            .map({ $0.vmaddr - $0.fileoff })
            .min() else {
            return nil
        }

        self.imageBaseAddress = imageBase
        self.segmentFormats = formats
        self.importedSymbols = symbols
    }

    func resolve(rawValue: UInt64, atFileOffset fileOffset: UInt64) -> Resolution? {
        guard let format = segmentFormats.first(where: { $0.fileRange.contains(fileOffset) })?.pointerFormat else {
            return nil
        }

        switch format {
        case 2, 6: // DYLD_CHAINED_PTR_64 / DYLD_CHAINED_PTR_64_OFFSET
            if (rawValue >> 63) != 0 {
                return importResolution(ordinal: Int(rawValue & 0x00FF_FFFF))
            }
            let target = (rawValue & 0x0000_000F_FFFF_FFFF)
                | (((rawValue >> 36) & 0xFF) << 56)
            return .fileOffset(format == 6 ? target : target &- imageBaseAddress)

        case 1, 7, 9, 10, 12: // arm64e formats used by Apple userland binaries
            let isBind = ((rawValue >> 62) & 1) != 0
            if isBind {
                let ordinalMask: UInt64 = format == 12 ? 0x00FF_FFFF : 0xFFFF
                return importResolution(ordinal: Int(rawValue & ordinalMask))
            }
            let isAuthenticated = (rawValue >> 63) != 0
            let target: UInt64
            if isAuthenticated {
                target = rawValue & 0xFFFF_FFFF
            } else {
                target = (rawValue & 0x0000_07FF_FFFF_FFFF)
                    | (((rawValue >> 43) & 0xFF) << 56)
            }
            // Apple's arm64e authenticated rebase layout always stores a
            // runtime offset from the image base, including pointer format 1.
            if isAuthenticated {
                return .fileOffset(target)
            }
            let usesImageOffset = [7, 9, 12].contains(Int(format))
            return .fileOffset(usesImageOffset ? target : target &- imageBaseAddress)

        default:
            return nil
        }
    }

    private func importResolution(ordinal: Int) -> Resolution? {
        guard importedSymbols.indices.contains(ordinal) else {
            return nil
        }
        return .importSymbol(importedSymbols[ordinal])
    }
}

public struct MachOFile {
    
	let url: URL
	let header: MachOHeader
	let commands: [MachOLoadCommandType]
    let segments: [MachOLoadCommand.Segment]
    let hasChainedFixups: Bool
    private let chainedFixups: MachOChainedFixups?
    
    let dataSlice: Data
	
	public init(url: URL, cpu: MachOCpuType?) throws {
		let data = try Data(contentsOf: url)
        try self.init(url: url, data: data, cpu: cpu)
	}
	
	public init(url: URL, data: Data, cpu: MachOCpuType?) throws {
		self.url = url
		
		let dataSlice: Data
		if let fatHeader = MachOFatHeader(data: data) {
            var fatArch: MachOFatArch?
            if let cpu = cpu {
                fatArch = fatHeader.architectures.first { $0.cputype == cpu.cputype }
            }
            if nil != fatArch {
                dataSlice = data[fatArch!];
            } else {
                throw MachOFileError.archFail;
            }
		} else {
			dataSlice = data
		}
        guard !dataSlice.isEmpty else {
            throw MachOFileError.truncated
        }
		let attributes = MachOFile.machAttributes(from: dataSlice)
        guard MachOFile.isSupportedMachMagic(attributes.magic) else {
            throw MachOFileError.invalidMachO
        }
		guard let header = MachOFile.header(from: dataSlice, attributes: attributes) else {
            throw MachOFileError.truncated
        }
        let parsedCommands = MachOFile.segmentCommands(from: dataSlice, header: header, attributes: attributes)
		
        self.dataSlice = dataSlice;
        self.header = header
		self.commands = parsedCommands.commands
        self.segments = parsedCommands.segments
        self.hasChainedFixups = parsedCommands.hasChainedFixups
        self.chainedFixups = MachOFile.chainedFixups(from: dataSlice,
                                                     header: header,
                                                     attributes: attributes,
                                                     segments: parsedCommands.segments)
	}
	
	private static func machAttributes(from data: Data) -> MachAttributes {
		let magic = data.extract(UInt32.self)
		let is64Bit = magic == MH_MAGIC_64 || magic == MH_CIGAM_64
		let isByteSwapped = magic == MH_CIGAM || magic == MH_CIGAM_64
		return MachAttributes(magic: magic, is64Bit: is64Bit, isByteSwapped: isByteSwapped)
	}
	
    private static func isSupportedMachMagic(_ magic: UInt32) -> Bool {
        return [MH_MAGIC, MH_MAGIC_64, MH_CIGAM, MH_CIGAM_64].contains(magic)
    }

	private static func header(from data: Data, attributes: MachAttributes) -> MachOHeader? {
		if attributes.is64Bit {
			guard let header = data.extractOptional(mach_header_64.self) else {
                return nil
            }
			return MachOHeader(header: header)
		} else {
			guard let header = data.extractOptional(mach_header.self) else {
                return nil
            }
			return MachOHeader(header: header)
		}
	}
	
	private static func segmentCommands(from data: Data, header: MachOHeader, attributes: MachAttributes) -> (commands: [MachOLoadCommandType], segments: [MachOLoadCommand.Segment], hasChainedFixups: Bool) {
		var segmentCommands: [MachOLoadCommandType] = []
        var segments: [MachOLoadCommand.Segment] = []
        var hasChainedFixups = false
		var offset = header.size
		for _ in 0..<header.loadCommandCount {
            guard let loadCommand = MachOLoadCommand(data: data, offset: offset, byteSwapped: attributes.isByteSwapped) else {
                break
            }
            let nextOffset = offset + loadCommand.size
            guard nextOffset >= offset, data.hasReadableRange(offset: offset, length: loadCommand.size) else {
                break
            }
            if loadCommand.command == UInt32(LC_DYLD_CHAINED_FIXUPS) {
                hasChainedFixups = true
            }
			if let command = loadCommand.command(from: data, offset: offset, byteSwapped: attributes.isByteSwapped) {
				segmentCommands.append(command)
                if let segment = command as? MachOLoadCommand.Segment {
                    segments.append(segment)
                }
			}
			offset = nextOffset
		}
		return (segmentCommands, segments, hasChainedFixups)
	}

    private static func chainedFixups(from data: Data,
                                      header: MachOHeader,
                                      attributes: MachAttributes,
                                      segments: [MachOLoadCommand.Segment]) -> MachOChainedFixups? {
        guard !attributes.isByteSwapped else {
            return nil
        }
        var offset = header.size
        for _ in 0..<header.loadCommandCount {
            guard let command = MachOLoadCommand(data: data,
                                                 offset: offset,
                                                 byteSwapped: attributes.isByteSwapped),
                  data.hasReadableRange(offset: offset, length: command.size) else {
                return nil
            }
            if command.command == UInt32(LC_DYLD_CHAINED_FIXUPS) {
                guard let linkedit: linkedit_data_command = data.extractOptional(linkedit_data_command.self,
                                                                                 offset: offset) else {
                    return nil
                }
                return MachOChainedFixups(data: data,
                                          payloadOffset: Int(linkedit.dataoff),
                                          payloadSize: Int(linkedit.datasize),
                                          segments: segments)
            }
            offset += command.size
        }
        return nil
    }

    func fileOffset(forVMAddress address: UInt64) -> UInt64? {
        for segment in segments {
            if let fileOffset = segment.fileOffset(forVMAddress: address) {
                return fileOffset
            }
        }
        return nil
    }

    func dataOffset(for pointer: SDPointer, size: Int = 1) -> Int? {
        if let directOffset = dataOffset(forAddress: pointer.address, size: size) {
            return directOffset
        }
        guard let fileOffset = fileOffset(forVMAddress: pointer.address) else {
            return nil
        }
        return dataOffset(forAddress: fileOffset, size: size)
    }

    func readValue<T>(at pointer: SDPointer) -> T? {
        guard let offset = dataOffset(for: pointer, size: MemoryLayout<T>.size) else {
            return nil
        }
        return dataSlice.readValue(offset)
    }

    func readCString(at pointer: SDPointer) -> String? {
        guard let offset = dataOffset(for: pointer) else {
            return nil
        }
        return dataSlice.readCString(from: offset)
    }

    func resolveRelative32Pointer(from pointer: SDPointer) -> SDPointer? {
        guard let relative: Int32 = readValue(at: pointer) else {
            return nil
        }
        return pointer.applying(relativeOffset: relative)
    }

    func resolveStoredPointer(at pointer: SDPointer) -> SDPointer? {
        guard let sourceOffset = dataOffset(for: pointer, size: MemoryLayout<UInt64>.size),
              let rawValue: UInt64 = dataSlice.readValue(sourceOffset),
              rawValue != 0 else {
            return nil
        }
        if let resolution = chainedFixups?.resolve(rawValue: rawValue,
                                                   atFileOffset: UInt64(sourceOffset)) {
            if case let .fileOffset(fileOffset) = resolution,
               dataOffset(forAddress: fileOffset, size: 1) != nil {
                return SDPointer(addr: fileOffset)
            }
            return nil
        }
        if let directOffset = dataOffset(forAddress: rawValue, size: 1) {
            return SDPointer(addr: UInt64(directOffset))
        }
        guard let fileOffset = fileOffset(forVMAddress: rawValue),
              dataOffset(forAddress: fileOffset, size: 1) != nil else {
            return nil
        }
        return SDPointer(addr: fileOffset)
    }

    func importedSymbol(at pointer: SDPointer) -> String? {
        guard let sourceOffset = dataOffset(for: pointer, size: MemoryLayout<UInt64>.size),
              let rawValue: UInt64 = dataSlice.readValue(sourceOffset),
              let resolution = chainedFixups?.resolve(rawValue: rawValue,
                                                      atFileOffset: UInt64(sourceOffset)),
              case let .importSymbol(symbol) = resolution else {
            return nil
        }
        return symbol
    }

    private func dataOffset(forAddress address: UInt64, size: Int) -> Int? {
        guard let offset = Int(exactly: address), dataSlice.hasReadableRange(offset: offset, length: size) else {
            return nil
        }
        return offset
    }
	
}
