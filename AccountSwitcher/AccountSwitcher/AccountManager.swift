import Foundation
import Security
import ZIPFoundation

// 游戏分身应用模型
struct AppTarget: Identifiable, Hashable {
    let id: String // Bundle ID 作为唯一标识
    let displayName: String
    let bundleID: String
    let dataContainerURL: URL
    let bundleContainerURL: URL?
}

class AccountManager {
    static let shared = AccountManager()

    // 账号文件存储主目录 (存放 .lrj 文件)
    var storageDir: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("AccountProfiles")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // 扫描系统中所有暗黑破坏神（包括所有分身与多开）
    func scanInstalledInstances() -> [AppTarget] {
        var targets: [AppTarget] = []
        let dataBasePath = URL(fileURLWithPath: "/var/mobile/Containers/Data/Application")
        let bundleBasePath = URL(fileURLWithPath: "/var/mobile/Containers/Bundle/Application")

        guard let dataDirs = try? FileManager.default.contentsOfDirectory(at: dataBasePath, includingPropertiesForKeys: nil) else {
            return targets
        }

        for dir in dataDirs {
            let metadataPlist = dir.appendingPathComponent(".com.apple.mobile_container_manager.metadata.plist")
            guard let dict = NSDictionary(contentsOf: metadataPlist),
                  let identifier = dict["MCMMetadataIdentifier"] as? String else {
                continue
            }

            // 过滤暗黑破坏神相关的 Bundle ID (支持官方、多开分身、修改版)
            let lowerID = identifier.lowercased()
            if lowerID.contains("diablo") || lowerID.contains("blizzard") || lowerID.contains("immortal") {
                var displayName = identifier
                var appBundleURL: URL? = nil

                // 尝试从 Bundle 目录获取真实 App 显示名
                if let bundleDirs = try? FileManager.default.contentsOfDirectory(at: bundleBasePath, includingPropertiesForKeys: nil) {
                    for bDir in bundleDirs {
                        let bMeta = bDir.appendingPathComponent(".com.apple.mobile_container_manager.metadata.plist")
                        if let bDict = NSDictionary(contentsOf: bMeta),
                           let bID = bDict["MCMMetadataIdentifier"] as? String,
                           bID == identifier {
                            appBundleURL = bDir
                            if let appFolder = try? FileManager.default.contentsOfDirectory(at: bDir, includingPropertiesForKeys: nil).first(where: { $0.pathExtension == "app" }),
                               let infoPlist = NSDictionary(contentsOf: appFolder.appendingPathComponent("Info.plist")) {
                                displayName = (infoPlist["CFBundleDisplayName"] as? String) ?? (infoPlist["CFBundleName"] as? String) ?? identifier
                            }
                            break
                        }
                    }
                }

                targets.append(AppTarget(
                    id: identifier,
                    displayName: displayName,
                    bundleID: identifier,
                    dataContainerURL: dir,
                    bundleContainerURL: appBundleURL
                ))
            }
        }
        return targets
    }

    // 1. 导出指定分身的账号备份 (.lrj)
    func exportAccount(target: AppTarget, name: String, completion: @escaping (Bool, String) -> Void) {
        let container = target.dataContainerURL
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        do {
            // 备份 Preferences (存有本地配置与部分Token)
            let prefsSrc = container.appendingPathComponent("Library/Preferences")
            let prefsDst = tempDir.appendingPathComponent("Preferences")
            if FileManager.default.fileExists(atPath: prefsSrc.path) {
                try FileManager.default.copyItem(at: prefsSrc, to: prefsDst)
            }

            // 备份 Application Support
            let appSupportSrc = container.appendingPathComponent("Library/Application Support")
            let appSupportDst = tempDir.appendingPathComponent("Application Support")
            if FileManager.default.fileExists(atPath: appSupportSrc.path) {
                try FileManager.default.copyItem(at: appSupportSrc, to: appSupportDst)
            }

            // 导出相关的 Keychain 数据
            let keychainData = dumpKeychainData(bundleID: target.bundleID)
            if let keychainData = keychainData {
                let kcFile = tempDir.appendingPathComponent("keychain.json")
                try keychainData.write(to: kcFile)
            }

            // 打包成 .lrj 文件
            let targetZip = storageDir.appendingPathComponent("\(name).lrj")
            if FileManager.default.fileExists(atPath: targetZip.path) {
                try FileManager.default.removeItem(at: targetZip)
            }
            try FileManager.default.zipItem(at: tempDir, to: targetZip)

            // 清理临时文件
            try? FileManager.default.removeItem(at: tempDir)
            completion(true, "导出成功: \(name).lrj")
        } catch {
            completion(false, "导出失败: \(error.localizedDescription)")
        }
    }

    // 2. 将 .lrj 注入并生效到指定的分身
    func applyAccount(target: AppTarget, fileURL: URL, completion: @escaping (Bool, String) -> Void) {
        let container = target.dataContainerURL

        // 强退游戏进程 (防止写入冲突)
        killGameProcess()

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            try FileManager.default.unzipItem(at: fileURL, to: tempDir)

            // 覆写沙盒关键文件
            let itemsToRestore = ["Preferences", "Application Support"]
            for item in itemsToRestore {
                let src = tempDir.appendingPathComponent(item)
                let dst = container.appendingPathComponent("Library/\(item)")
                if FileManager.default.fileExists(atPath: src.path) {
                    if FileManager.default.fileExists(atPath: dst.path) {
                        try FileManager.default.removeItem(at: dst)
                    }
                    try FileManager.default.copyItem(at: src, to: dst)
                }
            }

            // 恢复 Keychain 凭证
            let kcFile = tempDir.appendingPathComponent("keychain.json")
            if FileManager.default.fileExists(atPath: kcFile.path) {
                let data = try Data(contentsOf: kcFile)
                restoreKeychainData(data: data)
            }

            try? FileManager.default.removeItem(at: tempDir)
            completion(true, "已成功生效至 \(target.displayName)")
        } catch {
            completion(false, "生效失败: \(error.localizedDescription)")
        }
    }

    // 提取 Keychain 数据
    private func dumpKeychainData(bundleID: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let items = result as? [[String: Any]] {
            var exportList: [[String: String]] = []
            for item in items {
                if let service = item[kSecAttrService as String] as? String {
                    if service.contains("blizzard") || service.contains("diablo") || service.contains(bundleID) {
                        if let account = item[kSecAttrAccount as String] as? String,
                           let data = item[kSecValueData as String] as? Data {
                            exportList.append([
                                "service": service,
                                "account": account,
                                "data": data.base64EncodedString()
                            ])
                        }
                    }
                }
            }
            return try? JSONSerialization.data(withJSONObject: exportList, options: .prettyPrinted)
        }
        return nil
    }

    // 恢复 Keychain 数据
    private func restoreKeychainData(data: Data) {
        guard let list = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] else { return }
        for item in list {
            guard let service = item["service"],
                  let account = item["account"],
                  let base64 = item["data"],
                  let valData = Data(base64Encoded: base64) else { continue }

            let delQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account
            ]
            SecItemDelete(delQuery as CFDictionary)

            let addQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecValueData as String: valData
            ]
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    // 终止所有暗黑相关进程
    // 注：iOS SDK 不提供 Process/NSTask，这里通过 POSIX system() 调用 killall
    private func killGameProcess() {
        system("killall -9 DiabloImmortal")
    }
}
