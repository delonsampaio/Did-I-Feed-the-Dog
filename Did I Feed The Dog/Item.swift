//
//  Item.swift
//  Did I Feed The Dog?
//
//  Created by Delon Sampaio on 4/27/26.
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
