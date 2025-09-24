//
//  Copyright (c) 2025 Nikita Orlov
//  Licensed under the MIT License. See LICENSE for details.
//

import Foundation

extension Array {
    /// Splits the array into multiple arrays, each limited to the specified size.
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
    
    /// Splits the array into two halves.
    func halved() -> (firstHalf: [Element], secondHalf: [Element]) {
        let middleIndex = count / 2
        return (Array(self[..<middleIndex]), Array(self[middleIndex...]))
    }
}
