//
//  LocalJSONCoder.swift
//  messageai-swift
//
//  Split from Models.swift on 10/24/25.
//

import Foundation

enum LocalJSONCoder {
    static let encoder = JSONEncoder()
    static let decoder = JSONDecoder()

    static func encode<T: Encodable>(_ value: T) -> Data {
        (try? encoder.encode(value)) ?? Data()
    }

    static func decode<T: Decodable>(_ data: Data, fallback: T) -> T {
        (try? decoder.decode(T.self, from: data)) ?? fallback
    }
}
