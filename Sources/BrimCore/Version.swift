import Foundation

/// Compares dotted version strings ("1.10" > "1.9").
public func isVersion(_ a: String, newerThan b: String) -> Bool {
    let x = a.split(separator: ".").map { Int($0) ?? 0 }
    let y = b.split(separator: ".").map { Int($0) ?? 0 }
    for i in 0..<max(x.count, y.count) {
        let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
        if l != r { return l > r }
    }
    return false
}
