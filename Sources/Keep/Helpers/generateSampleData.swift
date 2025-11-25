//
//  generateSampleData.swift
//  Keep
//
//  Created by Michael Amiro on 24/04/2025.
//
import Foundation

private final class BundleToken {}

func generateSampleData(for fileName: String, `extension`: String = "json") -> Data {
    var data: Data
    let bundle = Bundle(for: BundleToken.self)
    guard let path = bundle.url(forResource: fileName, withExtension: `extension`) else {
        return fallbackSampleData()
    }
    do {
        data = try Data(contentsOf: path, options: .mappedIfSafe)
        return data
    } catch {
        return fallbackSampleData()
    }
}

private func fallbackSampleData() -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted]
    return (try? encoder.encode(Log.samples)) ?? Data()
}
