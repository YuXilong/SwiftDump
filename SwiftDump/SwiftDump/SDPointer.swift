//
//  SDPointer.swift
//  SwiftDump
//
//  Created by neilwu on 2020/6/26.
//  Copyright © 2020 nw. All rights reserved.
//

import Foundation

struct SDPointer {
    private(set) var address: UInt64
    
    init(addr: UInt64) {
        self.address = addr;
    }
    
    func add(_ offset: Int64) -> SDPointer {
        let delta = UInt64(bitPattern: offset)
        return SDPointer(addr: self.address &+ delta);
    }

    func applying(relativeOffset: Int32) -> SDPointer {
        return add(Int64(relativeOffset));
    }
    
    var desc: String {
        return self.address.hex;
    }
}
