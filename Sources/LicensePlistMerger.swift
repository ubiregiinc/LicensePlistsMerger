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
    enum Style {
        case licensePlist
        case licenseList

        init?(string: String) {
            switch string {
            case "LicensePlist", "licensePlist", "license-plist":
                self = .licensePlist
            case "LicenseList", "licenseList", "license-list":
                self = .licenseList
            default:
                return nil
            }
        }

        var fileName: String {
            switch self {
            case .licensePlist:
                return "Acknowledgements"
            case .licenseList:
                return "license-list"
            }
        }
    }

    @Argument(help: "統合したいライセンスファイルのpath")
    var inputs: [String]

    @Option(name: .long, help: "他のライセンスファイルのディレクトリのpath")
    var otherLicensesDirectoryPath: String?

    @Option(name: .long, help: "出力するplistのスタイル(license-plist/license-list)")
    var style: String?

    @Option(name: .short, help: "output")
    var output: String?

    func run() throws {
        var licenses = inputs
            .compactMap { Self.loadPlist(fileURL: URL(filePath: $0)) }
            .flatMap { $0 }

        let otherLicenses = otherLicensesDirectoryPath.flatMap { Self.otherLicenses(directoryURL: URL(filePath: $0)) } ?? []

        licenses = (licenses + otherLicenses).sorted { lhs, rhs in
            // 大文字小文字区別なしでソート
            return lhs.name.localizedCompare(rhs.name) == .orderedAscending
        }

        let plistStyle: Style
        if let style {
            plistStyle = Style(string: style) ?? .licensePlist
        } else {
            plistStyle = .licensePlist
        }

        let name: String
        let directoryURL: URL
        if let output {
            let rootPlistPath = URL(filePath: output)
            if rootPlistPath.pathExtension == "plist" {
                name = rootPlistPath.deletingPathExtension().lastPathComponent
            } else {
                name = rootPlistPath.lastPathComponent
            }
            directoryURL = rootPlistPath.deletingLastPathComponent()
        } else {
            name = plistStyle.fileName
            directoryURL = URL(filePath: FileManager.default.currentDirectoryPath)
        }

        switch plistStyle {
        case .licensePlist:
            try Self.writePlists(name: name, directoryURL: directoryURL, licenses: licenses)
        case .licenseList:
            try Self.mergedLicenseListPlist(url: directoryURL.appending(path: "\(name).plist"), licenses: licenses)
        }
    }
}

extension LicensesPlistMerger {
    static func loadPlist(fileURL: URL) -> [LicenseInfo]? {
        guard let data = try? Data(contentsOf: fileURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let plist = plist as? [AnyHashable: Any] else { return nil }

        if let array = plist["PreferenceSpecifiers"] as? [[String: String]] {
            return Self.cocoapodsLicenses(array: array)
        } else if let array = plist["libraries"] as? [[String: String]] {
            return Self.licenseListLicenses(array: array)
        } else {
            return nil
        }
    }

    static func cocoapodsLicenses(array: [[String: String]]) -> [LicenseInfo] {
        array.compactMap { dictionary in
            guard let name = dictionary["Title"],
                  !name.isEmpty,
                  name != "Acknowledgements", // CocoaPodsが挿入する項目
                  let body = dictionary["FooterText"] else { return nil }
            // XcodeのPlistViewerでplistが開けない文字FF(0x0c)を取り除く(ZBarSDK向け)
            return LicenseInfo(name: name, body: body.replacingOccurrences(of: "\u{0c}", with: ""))
        }
    }

    static func licenseListLicenses(array: [[String: String]]) -> [LicenseInfo] {
        array.compactMap { dictionary in
            guard let name = dictionary["name"], let body = dictionary["licenseBody"] else { return nil }
            return LicenseInfo(name: name, body: body.replacingOccurrences(of: "\u{0c}", with: ""))
        }
    }

    static func otherLicenses(directoryURL: URL) -> [LicenseInfo]? {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: directoryURL.path(), isDirectory: &isDirectory)
        guard exists && isDirectory.boolValue else { return nil }

        do {
            let directories = try fileManager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil).compactMap { url in
                var directory: ObjCBool = false
                _ = fileManager.fileExists(atPath: url.path(), isDirectory: &directory)

                return directory.boolValue ? url : nil
            }
            return directories.compactMap { otherLicense(directoryURL: $0) }
        } catch {
            print(error)
            return nil
        }
    }

    static func otherLicense(directoryURL: URL) -> LicenseInfo? {
        do {
            let fileManager = FileManager.default
            let files = try fileManager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil)
            let licenseURL = files.first { url in
                let name = url.deletingPathExtension().lastPathComponent
                return name == "LICENSE" || name == "LICENCE"
            }
            guard let licenseURL,
                  let body = String(data: try Data(contentsOf: licenseURL), encoding: .utf8) else { return nil }

            return LicenseInfo(name: directoryURL.lastPathComponent, body: body)
        } catch {
            print(error)
            return nil
        }
    }

    static func writePlists(name: String, directoryURL: URL, licenses: [LicenseInfo]) throws {
        let childrenDirectory = directoryURL.appending(path: name, directoryHint: .isDirectory)

        do {
            try FileManager.default.createDirectory(at: childrenDirectory, withIntermediateDirectories: true)
        } catch {
            let error = error as NSError
            if error.domain != NSCocoaErrorDomain || error.code != NSFileWriteFileExistsError {
                throw error
            }
        }

        for license in licenses {
            try Self.writeChildPlist(directoryURL: childrenDirectory, license: license)
        }

        try Self.deleteOrphanPlists(directoryURL: childrenDirectory, licenses: licenses)

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

    /// なくなったライブラリのファイルを削除する
    static func deleteOrphanPlists(directoryURL: URL, licenses: [LicenseInfo]) throws {
        let urls = try FileManager.default.contentsOfDirectory(at: directoryURL,
                                                               includingPropertiesForKeys: nil)

        for url in urls {
            let fileName = url.deletingPathExtension().lastPathComponent
            if !licenses.contains(where: { $0.name == fileName }) {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    static func mergedLicenseListPlist(url: URL, licenses: [LicenseInfo]) throws {
        let dictionary: [String: [[String: String]]] = [
            "libraries": licenses.map { ["name": $0.name, "licenseBody": $0.body] }
        ]

        let plist = try PropertyListSerialization.data(fromPropertyList: dictionary, format: .xml, options: .zero)
        try plist.write(to: url)

        licenses.forEach { print($0.name) }
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
