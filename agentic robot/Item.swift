//
//  Item.swift
//  agentic robot
//
//  Created by q2 on 12/5/26.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
