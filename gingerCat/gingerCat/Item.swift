//
//  Item.swift
//  gingerCat
//
//  Created by fsy on 2026/4/8.
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
