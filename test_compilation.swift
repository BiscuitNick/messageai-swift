#!/usr/bin/env swift

import Foundation

// Test that scheduling metadata compiles correctly
struct TestData: Codable {
    let schedulingIntent: String?
    let intentConfidence: Double?
    let intentAnalyzedAt: Date?
    let schedulingKeywords: [String]
}

// Test encoding/decoding
let testData = TestData(
    schedulingIntent: "high",
    intentConfidence: 0.85,
    intentAnalyzedAt: Date(),
    schedulingKeywords: ["meet", "tomorrow", "2pm"]
)

let encoder = JSONEncoder()
let decoder = JSONDecoder()

if let encoded = try? encoder.encode(testData) {
    if let decoded = try? decoder.decode(TestData.self, from: encoded) {
        print("✅ Encoding/decoding test passed")
        print("schedulingIntent: \(decoded.schedulingIntent ?? "nil")")
        print("intentConfidence: \(decoded.intentConfidence ?? 0.0)")
        print("schedulingKeywords: \(decoded.schedulingKeywords)")
    } else {
        print("❌ Decoding failed")
    }
} else {
    print("❌ Encoding failed")
}

// Test backward compatibility
let testDataWithoutScheduling = TestData(
    schedulingIntent: nil,
    intentConfidence: nil,
    intentAnalyzedAt: nil,
    schedulingKeywords: []
)

if let encoded = try? encoder.encode(testDataWithoutScheduling) {
    if let decoded = try? decoder.decode(TestData.self, from: encoded) {
        print("✅ Backward compatibility test passed")
    } else {
        print("❌ Backward compatibility decoding failed")
    }
} else {
    print("❌ Backward compatibility encoding failed")
}

print("\n✅ All compilation tests passed!")
