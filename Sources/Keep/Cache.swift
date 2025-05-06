//
//  Cache.swift
//  Keep
//
//  Created by Michael Amiro on 24/04/2025.
//

import Foundation

final class Cache<Key: Hashable, Value> {
    private let wrapped = NSCache<WrappedKey, Entry>()
    private let dateProvider: () -> Date
    private let lifetime: TimeInterval
    private let keyTracker = KeyTracker()

    init(dateProvider: @escaping () -> Date = Date.init,
         lifetime: TimeInterval = 12 * 60 * 60,
         maximumEntryCount: Int = 50) {
        self.dateProvider = dateProvider
        self.lifetime = lifetime
        wrapped.countLimit = maximumEntryCount
        wrapped.delegate = keyTracker
    }

    func insert(_ value: Value, forKey key: Key) {
        let date = dateProvider().addingTimeInterval(lifetime)
        let entry = Entry(key: key, value: value, expiry: date)
        wrapped.setObject(entry, forKey: WrappedKey(key))
        print("Inserting value for key: \(key)")
        keyTracker.keys.insert(key)
    }

    func value(forKey key: Key) -> Value? {
        print("Fetching value for key: \(key)")
        guard let entry = wrapped.object(forKey: WrappedKey(key)) else {
            return nil
        }
        guard dateProvider() < entry.expiry else {
            removeValue(forKey: key)
            return nil
        }
        return entry.value
    }

    func removeValue(forKey key: Key) {
        wrapped.removeObject(forKey: WrappedKey(key))
    }

    func removeAll() {
        wrapped.removeAllObjects()
    }

    func allValues() -> [Value] {
        return keyTracker.keys.compactMap { key in
            value(forKey: key)
        }
    }
}

extension Cache {
    subscript(key: Key) -> Value? {
        get {
            return value(forKey: key)
        }
        set {
            guard let value = newValue else {
                removeValue(forKey: key)
                return
            }
            insert(value, forKey: key)
        }
    }
}

private extension Cache {
    final class WrappedKey: NSObject {
        let key: Key

        init(_ key: Key) {
            self.key = key
        }

        override var hash: Int { return key.hashValue }

        override func isEqual(_ object: Any?) -> Bool {
            guard let value = object as? WrappedKey else {
                return false
            }
            return value.key == key
        }
    }

    final class Entry {
        let key: Key
        let value: Value
        let expiry: Date
        
        init(key: Key, value: Value, expiry: Date) {
            self.key = key
            self.value = value
            self.expiry = expiry
        }
    }
    
    final class KeyTracker: NSObject, NSCacheDelegate {
        var keys = Set<Key>()
        func cache(_ cache: NSCache<AnyObject, AnyObject>, willEvictObject obj: Any) {
            guard let entry = obj as? Entry else { return }
            keys.remove(entry.key)
        }
    }
    
    func entry(forKey key: Key) -> Entry? {
        guard let entry = wrapped.object(forKey: WrappedKey(key)) else {
            return nil
        }
        guard dateProvider() < entry.expiry else {
            removeValue(forKey: key)
            return nil
        }
        return entry
    }
    
    func insert(_ entry: Entry) {
        wrapped.setObject(entry, forKey: WrappedKey(entry.key))
        keyTracker.keys.insert(entry.key)
    }
}

extension Cache: Codable where Key: Codable, Value: Codable {
    convenience init(from decoder: Decoder) throws {
        self.init()

        let container = try decoder.singleValueContainer()
        let entries = try container.decode([Entry].self)
        entries.forEach(insert)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(keyTracker.keys.compactMap { self.entry(forKey: $0) })
    }
}

extension Cache.Entry: Codable where Key: Codable, Value: Codable {
    enum CodingKeys: String, CodingKey {
        case key, value, expiry
    }

    convenience init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let key = try container.decode(Key.self, forKey: .key)
        let value = try container.decode(Value.self, forKey: .value)
        let expiry = try container.decode(Date.self, forKey: .expiry)
        self.init(key: key, value: value, expiry: expiry)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(key, forKey: .key)
        try container.encode(value, forKey: .value)
        try container.encode(expiry, forKey: .expiry)
    }
}
