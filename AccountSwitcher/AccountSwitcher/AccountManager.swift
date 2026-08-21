import Foundation
import Security
import ZIPFoundation

// 应用模型
struct AppTarget: Identifiable, Hashable {
    var id: String { bundleID + "_" + (dataContainerURL.path) }
    let displayName: String
    let bundleID: String
    let dataContainerURL: URL
    let bundleURL: URL?
    let isUserApp: Bool
}

class AccountManager {
    static let shared = AccountManager()

    var storageDir: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("AccountProfiles")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // 扫描系统中【所有】已安装的应用（官方、巨魔、多开、分身）
    func scanAllInstalledApps() -> [AppTarget] {
        var targets: [AppTarget] = []
        var seenPaths = Set<String>()

        // 方案 1：优先使用 LSApplicationWorkspace 私有类获取
        if let workspaceClass = NSClassFromString("LSApplicationWorkspace") as? NSObject.Type,
           let workspace = workspaceClass.perform(NSSelectorFromString("defaultWorkspace"))?.takeUnretainedValue() as? NSObject,
           let apps = workspace.perform(NSSelectorFromString("allApplications"))?.takeUnretainedValue() as? [NSObject] {

            for appProxy in apps {
                guard let bundleID = appProxy.value(forKey: "applicationIdentifier") as? String,
                      let dataURL = appProxy.value(forKey: "dataContainerURL") as? URL else {
                    continue
                }

                let localizedName = (appProxy.value(forKey: "localizedName") as? String) ?? bundleID
                let bundleURL = appProxy.value(forKey: "bundleURL") as? URL
                let appType = (appProxy.value(forKey: "applicationType") as? String) ?? "User"

                seenPaths.insert(dataURL.path)

                targets.append(AppTarget(
                    displayName: localizedName.isEmpty ? bundleID : localizedName,
                    bundleID: bundleID,
                    dataContainerURL: dataURL,
                    bundleURL: bundleURL,
                    isUserApp: appType == "User"
                ))
            }
        }

        // 方案 2：全盘扫描 /var/mobile/Containers/Data/Application 兜底，防止私有API漏掉多开
        let dataBasePath = URL(fileURLWithPath: "/var/mobile/Containers/Data/Application")
        if let subdirs = try? FileManager.default.contentsOfDirectory(at: dataBasePath, includingPropertiesForKeys: nil) {
            for dir in subdirs {
                if seenPaths.contains(dir.path) { continue }

                let metaPlist = dir.appendingPathComponent(".com.apple.mobile_container_manager.metadata.plist")
                var identifier = dir.lastPathComponent

                if let dict = NSDictionary(contentsOf: metaPlist),
                   let mcmID = dict["MCMMetadataIdentifier"] as? String {
                    identifier = mcmID
                }

                targets.append(AppTarget(
                    displayName: "[未知/分身] \(identifier)",
                    bundleID: identifier,
                    dataContainerURL: dir,
                    bundleURL: nil,
                    isUserApp: true
                ))
            }
        }

        // 优先将用户安装的应用和包含 diablo / 暗黑 的排在最前面
        return targets.sorted { a, b in
            let aIsDiablo = a.displayName.contains("暗黑") || a.bundleID.lowercased().contains("diablo") || a.bundleID.lowercased().contains("blizzard")
            let bIsDiablo = b.displayName.contains("暗黑") || b.bundleID.lowercased().contains("diablo") || b.bundleID.lowercased().contains("blizzard")
            if aIsDiablo && !bIsDiablo { return true }
            if !aIsDiablo && bIsDiablo { return false }
            return a.displayName.localizedCompare(b.displayName) == .orderedAscending
        }
    }

    // 1. 导出账号备份 (.lrj)
    // 耗时文件操作在后台线程执行，完成后切回主线程更新 UI
    func exportAccount(target: AppTarget, name: String, completion: @escaping (Bool, String) -> Void) {
        let container = target.dataContainerURL

        DispatchQueue.global(qos: .userInitiated).async {
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

            var result: (Bool, String)

            do {
                // 备份 Preferences (使用降级拷贝，FileManager 失败时自动用 cp -rf)
                let prefsSrc = container.appendingPathComponent("Library/Preferences")
                let prefsDst = tempDir.appendingPathComponent("Preferences")
                if FileManager.default.fileExists(atPath: prefsSrc.path) {
                    try self.copyItemWithFallback(from: prefsSrc, to: prefsDst)
                }

                // 备份 Application Support
                let appSupportSrc = container.appendingPathComponent("Library/Application Support")
                let appSupportDst = tempDir.appendingPathComponent("Application Support")
                if FileManager.default.fileExists(atPath: appSupportSrc.path) {
                    try self.copyItemWithFallback(from: appSupportSrc, to: appSupportDst)
                }

                // 备份 Documents (有些游戏会将Token存在这里)
                let docsSrc = container.appendingPathComponent("Documents")
                let docsDst = tempDir.appendingPathComponent("Documents")
                if FileManager.default.fileExists(atPath: docsSrc.path) {
                    try self.copyItemWithFallback(from: docsSrc, to: docsDst)
                }

                // 导出相关的 Keychain 数据
                if let keychainData = self.dumpKeychainData(bundleID: target.bundleID) {
                    let kcFile = tempDir.appendingPathComponent("keychain.json")
                    try keychainData.write(to: kcFile)
                }

                // 打包为 .lrj
                let targetZip = self.storageDir.appendingPathComponent("\(name).lrj")
                if FileManager.default.fileExists(atPath: targetZip.path) {
                    try FileManager.default.removeItem(at: targetZip)
                }
                try FileManager.default.zipItem(at: tempDir, to: targetZip)

                try? FileManager.default.removeItem(at: tempDir)
                result = (true, "导出成功: \(name).lrj")
            } catch {
                try? FileManager.default.removeItem(at: tempDir)
                result = (false, "导出失败: \(error.localizedDescription)")
            }

            // 切回主线程回调
            DispatchQueue.main.async {
                completion(result.0, result.1)
            }
        }
    }

    // 2. 将 .lrj 注入生效到指定分身
    // 耗时文件操作在后台线程执行，完成后切回主线程更新 UI
    func applyAccount(target: AppTarget, fileURL: URL, completion: @escaping (Bool, String) -> Void) {
        let container = target.dataContainerURL

        DispatchQueue.global(qos: .userInitiated).async {
            // 强退进程
            self.killAllDiablo()

            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            var result: (Bool, String)

            do {
                try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                try FileManager.default.unzipItem(at: fileURL, to: tempDir)

                // 恢复 Preferences、Application Support、Documents (使用降级拷贝)
                let itemsToRestore = ["Preferences", "Application Support", "Documents"]
                for item in itemsToRestore {
                    let src = tempDir.appendingPathComponent(item)
                    let dst = item == "Documents" ? container.appendingPathComponent("Documents") : container.appendingPathComponent("Library/\(item)")

                    if FileManager.default.fileExists(atPath: src.path) {
                        if FileManager.default.fileExists(atPath: dst.path) {
                            try? FileManager.default.removeItem(at: dst)
                        }
                        try self.copyItemWithFallback(from: src, to: dst)
                    }
                }

                // 恢复 Keychain
                let kcFile = tempDir.appendingPathComponent("keychain.json")
                if FileManager.default.fileExists(atPath: kcFile.path) {
                    let data = try Data(contentsOf: kcFile)
                    self.restoreKeychainData(data: data)
                }

                try? FileManager.default.removeItem(at: tempDir)
                result = (true, "已成功生效至 \(target.displayName)")
            } catch {
                try? FileManager.default.removeItem(at: tempDir)
                result = (false, "生效失败: \(error.localizedDescription)")
            }

            // 切回主线程回调
            DispatchQueue.main.async {
                completion(result.0, result.1)
            }
        }
    }

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
                    // 放宽匹配规则，包含通用凭证
                    if service.lowercased().contains("blizzard") ||
                       service.lowercased().contains("diablo") ||
                       service.contains(bundleID) ||
                       service.lowercased().contains("battle.net") {
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
    // 注：iOS SDK 不提供 Process/NSTask/system()，使用 posix_spawn 调用 killall
    private func killAllDiablo() {
        var pid: pid_t = 0
        var argv: [UnsafeMutablePointer<CChar>?] = [
            strdup("killall"),
            strdup("-9"),
            strdup("DiabloImmortal"),
            nil
        ]
        var envp: [UnsafeMutablePointer<CChar>?] = [nil]
        posix_spawn(&pid, "/usr/bin/killall", nil, nil, &argv, &envp)
        for i in 0..<3 { free(argv[i]) }
        if pid > 0 {
            var status: Int32 = 0
            waitpid(pid, &status, 0)
        }
    }

    // 降级拷贝：FileManager.copyItem 失败时，用 posix_spawn 调 cp -rf 跨沙盒拷贝
    private func copyItemWithFallback(from src: URL, to dst: URL) throws {
        // 先尝试 FileManager 标准拷贝
        do {
            try FileManager.default.copyItem(at: src, to: dst)
        } catch {
            // FileManager 失败，降级用 cp -rf
            let result = spawnCp(src: src, dst: dst)
            if !result {
                throw error
            }
        }
    }

    // 通过 posix_spawn 调用 /bin/cp -rf 实现跨沙盒拷贝
    private func spawnCp(src: URL, dst: URL) -> Bool {
        var pid: pid_t = 0
        var argv: [UnsafeMutablePointer<CChar>?] = [
            strdup("cp"),
            strdup("-rf"),
            strdup(src.path),
            strdup(dst.path),
            nil
        ]
        var envp: [UnsafeMutablePointer<CChar>?] = [nil]
        let ret = posix_spawn(&pid, "/bin/cp", nil, nil, &argv, &envp)
        for i in 0..<4 { free(argv[i]) }
        if ret != 0 {
            return false
        }
        if pid > 0 {
            var status: Int32 = 0
            waitpid(pid, &status, 0)
            return status == 0
        }
        return false
    }
}
