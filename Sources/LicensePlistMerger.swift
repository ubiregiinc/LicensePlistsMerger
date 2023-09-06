//
//  LicensesPlistMerger.swift
//  
//
//  Created by Ryotaro Seki on 2023/08/28.
//

import ArgumentParser
import Foundation

#if canImport(Darwin)
import Darwin
#endif

@main
struct LicensesPlistMerger: ParsableCommand {
    static let name = "Acknowledgements"

    @Option(name: .long, help: "CocoaPodsのplistのpath")
    var cocoapodsPlistPath: String?

    @Option(name: .long, help: "LicenseListのplistのpath")
    var licenseListPlistPath: String?

    @Option(name: .short, help: "output")
    var output: String?

    func run() throws {
        guard let cocoapodsPlistPath else {
            print("cocoapods-plist-path not set!")
            #if canImport(Darwin)
            Darwin.exit(1)
            #else
            return
            #endif
        }
        guard let licenseListPlistPath else {
            print("license-list-plist-path not set!")
            #if canImport(Darwin)
            Darwin.exit(1)
            #else
            return
            #endif
        }

        let currentURL = URL(filePath: FileManager.default.currentDirectoryPath)
        let cocoapodsURL = currentURL.appending(path: cocoapodsPlistPath)

        guard let cocoapodsLicenses = Self.cocoapodsLicenses(fileURL: cocoapodsURL) else {
            print("cocoapods licenses processing error")
            #if canImport(Darwin)
            Darwin.exit(1)
            #else
            return
            #endif
        }

        let licenseListURL = currentURL.appending(path: licenseListPlistPath)
        guard let licenseListLicenses = Self.licenseListLicenses(fileURL: licenseListURL) else {
            print("LicenseList licenses processing error")
            #if canImport(Darwin)
            Darwin.exit(1)
            #else
            return
            #endif
        }

        let licenses = (cocoapodsLicenses + licenseListLicenses).sorted { lhs, rhs in
            // 大文字小文字区別なしでソート
            return lhs.name.localizedCompare(rhs.name) == .orderedAscending
        }

        let name: String
        let directoryURL: URL
        if let output {
            let rootPlistPath = currentURL.appending(path: output)
            if rootPlistPath.pathExtension == "plist" {
                name = rootPlistPath.deletingPathExtension().lastPathComponent
            } else {
                name = rootPlistPath.lastPathComponent
            }
            directoryURL = rootPlistPath.deletingLastPathComponent()
        } else {
            name = Self.name
            directoryURL = currentURL
        }

        try Self.writePlists(name: name, directoryURL: directoryURL, licenses: licenses)
    }
}

extension LicensesPlistMerger {
    static func cocoapodsLicenses(fileURL: URL) -> [LicenseInfo]? {
        guard let data = try? Data(contentsOf: fileURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let plist = plist as? [AnyHashable: Any],
              let array = plist["PreferenceSpecifiers"] as? [[String: String]] else { return nil }

        return array.compactMap { dictionary in
            guard let name = dictionary["Title"],
                  !name.isEmpty,
                  name != "Acknowledgements", // CocoaPodsが挿入する項目
                  let body = dictionary["FooterText"] else { return nil }
            // XcodeのPlistViewerでplistが開けない文字FF(0x0c)を取り除く(ZBarSDK向け)
            return LicenseInfo(name: name, body: body.replacingOccurrences(of: "\u{0c}", with: ""))
        }
    }

    static func licenseListLicenses(fileURL: URL) -> [LicenseInfo]? {
        guard let data = try? Data(contentsOf: fileURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let plist = plist as? [AnyHashable: Any],
              let array = plist["libraries"] as? [[String: String]] else { return nil }

        return array.compactMap { dictionary in
            guard let name = dictionary["name"], let body = dictionary["licenseBody"] else { return nil }
            return LicenseInfo(name: name, body: body.replacingOccurrences(of: "\u{0c}", with: ""))
        }
    }
}

extension LicensesPlistMerger {
    static func writePlists(name: String, directoryURL: URL, licenses: [LicenseInfo]) throws {
        let childrenDirectory = directoryURL.appending(path: name, directoryHint: .isDirectory)

        do {
            try FileManager.default.createDirectory(at: childrenDirectory, withIntermediateDirectories: false)
        } catch {
            let error = error as NSError
            if error.domain != NSCocoaErrorDomain || error.code != NSFileWriteFileExistsError {
                throw error
            }
        }

        for license in licenses {
            try Self.writeChildPlist(directoryURL: childrenDirectory, license: license)
        }

        try Self.writeRootPlist(name: name, licenses: licenses, url: directoryURL)
    }

    static func writeRootPlist(name: String, licenses: [LicenseInfo], url: URL) throws {
        let licenses: [[String: String]] = licenses.map { license in
            ["File": "\(name)/\(license.name)",
             "Title": license.name,
             "Type": "PSChildPaneSpecifier"]
        }
        let dictionary: [String : [[String: String]]] = [
            "PreferenceSpecifiers": [["Title": "Licenses", "Type": "PSGroupSpecifier"]] + licenses
        ]

        let plist = try PropertyListSerialization.data(fromPropertyList: dictionary, format: .xml, options: .zero)

        try plist.write(to: url.appending(path: "\(name).plist"))
    }

    static func writeChildPlist(directoryURL: URL, license: LicenseInfo) throws {
        let plist = try license.plist()

        try plist.write(to: directoryURL.appending(path: "\(license.name).plist"))
        print(license.name)
    }
}

struct LicenseInfo {
    /// ライセンスが適用されるライブラリの名前
    let name: String
    /// ライセンス本文
    let body: String

    func plist() throws -> Data {
        let dictionary: [String: [[String: String]]] = [
            "PreferenceSpecifiers": [["FooterText": body, "Type": "PSGroupSpecifier"]]]

        return try PropertyListSerialization.data(fromPropertyList: dictionary, format: .xml, options: .zero)
    }
}
