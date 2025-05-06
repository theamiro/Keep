//
//  generateSampleData.swift
//  Keep
//
//  Created by Michael Amiro on 24/04/2025.
//
import Foundation

func generateSampleData(for fileName: String, `extension`: String = "json") -> Data {
    var data: Data
    guard let path = Bundle.module.url(forResource: fileName, withExtension: `extension`) else {
        return Data()
    }
    print(path)
    do {
        data = try Data(contentsOf: path, options: .mappedIfSafe)
        return data
    } catch {
        return Data()
    }
}
