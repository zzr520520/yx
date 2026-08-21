import SwiftUI

struct ProfileItem: Identifiable {
    let id = UUID()
    let name: String
    let size: String
    let fileURL: URL
}

// 全部应用选择弹窗
struct AppPickerView: View {
    let apps: [AppTarget]
    @Binding var selectedApp: AppTarget?
    @Environment(\.presentationMode) var presentationMode
    @State private var searchText = ""

    var filteredApps: [AppTarget] {
        if searchText.isEmpty { return apps }
        return apps.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText) ||
            $0.bundleID.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationView {
            VStack {
                TextField("🔍 搜索应用名称或 Bundle ID...", text: $searchText)
                    .padding(8)
                    .background(Color(UIColor.systemGray6))
                    .cornerRadius(8)
                    .padding(.horizontal)

                List(filteredApps) { app in
                    Button(action: {
                        selectedApp = app
                        presentationMode.wrappedValue.dismiss()
                    }) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(app.displayName)
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                Spacer()
                                if selectedApp?.id == app.id {
                                    Image(systemName: "checkmark").foregroundColor(.blue)
                                }
                            }
                            Text(app.bundleID)
                                .font(.caption)
                                .foregroundColor(.gray)
                            Text(app.dataContainerURL.path)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        .padding(.vertical, 2)
                    }
                }
                .listStyle(PlainListStyle())
            }
            .navigationTitle("选择目标应用")
            .navigationBarItems(trailing: Button("关闭") {
                presentationMode.wrappedValue.dismiss()
            })
        }
    }
}

struct ContentView: View {
    @State private var allApps: [AppTarget] = []
    @State private var selectedTarget: AppTarget? = nil
    @State private var showAppPicker = false

    @State private var profileList: [ProfileItem] = []
    @State private var activeFileName: String = ""
    @State private var alertMsg = ""
    @State private var showAlert = false
    @State private var inputAccountName = ""
    @State private var showInputDialog = false
    @State private var isProcessing = false
    @State private var processingText = ""

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // 顶部目标应用卡片
                Button(action: { showAppPicker = true }) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("当前选定目标:")
                                .font(.caption)
                                .foregroundColor(.gray)
                            if let target = selectedTarget {
                                Text(target.displayName)
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.blue)
                                Text(target.bundleID)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            } else {
                                Text("点击选择应用 (支持全盘所有App及多开)")
                                    .font(.subheadline)
                                    .foregroundColor(.red)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(.gray)
                    }
                    .padding()
                    .background(Color(UIColor.secondarySystemBackground))
                }

                // 标签栏
                HStack(spacing: 30) {
                    Text("YOLO文件").foregroundColor(.gray)
                    Text("脚本文件").bold().foregroundColor(.blue)
                        .overlay(Rectangle().frame(height: 2).foregroundColor(.blue), alignment: .bottom)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 12)

                Divider().padding(.vertical, 8)

                // 表头
                HStack {
                    Text("生效").frame(width: 35, alignment: .leading)
                    Text("文件名").frame(maxWidth: .infinity, alignment: .leading)
                    Text("大小").frame(width: 65, alignment: .leading)
                    Text("操作").frame(width: 110, alignment: .center)
                }
                .font(.caption)
                .foregroundColor(.gray)
                .padding(.horizontal)

                // 账号列表
                List {
                    ForEach(profileList) { item in
                        HStack {
                            Image(systemName: activeFileName == item.name ? "checkmark" : "")
                                .foregroundColor(.black)
                                .frame(width: 25)

                            Text(item.name)
                                .lineLimit(1)
                                .font(.system(size: 14))
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Text(item.size)
                                .font(.caption2)
                                .foregroundColor(.gray)
                                .frame(width: 65, alignment: .leading)

                            HStack(spacing: 6) {
                                Button("生效") {
                                    guard let target = selectedTarget else {
                                        alertMsg = "请先点击顶部选择目标应用！"
                                        showAlert = true
                                        return
                                    }
                                    isProcessing = true
                                    processingText = "正在生效..."
                                    AccountManager.shared.applyAccount(target: target, fileURL: item.fileURL) { success, msg in
                                        isProcessing = false
                                        if success { activeFileName = item.name }
                                        alertMsg = msg
                                        showAlert = true
                                    }
                                }
                                .disabled(isProcessing)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(isProcessing ? Color.gray : Color.blue)
                                .foregroundColor(.white)
                                .font(.caption)
                                .cornerRadius(4)

                                Button("删除") {
                                    try? FileManager.default.removeItem(at: item.fileURL)
                                    loadFiles()
                                }
                                .disabled(isProcessing)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.red)
                                .foregroundColor(.white)
                                .font(.caption)
                                .cornerRadius(4)
                            }
                            .frame(width: 110)
                        }
                    }
                }
                .listStyle(PlainListStyle())

                // 底部备份按钮
                Button(action: {
                    if selectedTarget == nil {
                        alertMsg = "请先点击顶部选择要备份的应用"
                        showAlert = true
                    } else {
                        showInputDialog = true
                    }
                }) {
                    Text(selectedTarget == nil ? "请先选择目标应用" : "备份当前 [\(selectedTarget!.displayName)] 数据")
                        .bold()
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(selectedTarget == nil ? Color.gray : (isProcessing ? Color.gray : Color.blue))
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .disabled(selectedTarget == nil || isProcessing)
                .padding()
            }
            .navigationTitle("账号数据管理")
            // Loading 遮罩
            .overlay(
                Group {
                    if isProcessing {
                        ZStack {
                            Color.black.opacity(0.4)
                                .ignoresSafeArea()
                            VStack(spacing: 12) {
                                ProgressView()
                                    .scaleEffect(1.5)
                                Text(processingText)
                                    .foregroundColor(.white)
                                    .font(.headline)
                            }
                            .padding(30)
                            .background(Color(UIColor.systemBackground))
                            .cornerRadius(12)
                        }
                    }
                }
            )
            .sheet(isPresented: $showAppPicker) {
                AppPickerView(apps: allApps, selectedApp: $selectedTarget)
            }
            .sheet(isPresented: $showInputDialog) {
                VStack(spacing: 20) {
                    Text("输入备份文件名").font(.headline)
                    TextField("例如: 暗黑破坏神(787)", text: $inputAccountName)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .padding()
                    Button("立即导出") {
                        showInputDialog = false
                        guard let target = selectedTarget, !inputAccountName.isEmpty else { return }
                        isProcessing = true
                        processingText = "正在备份..."
                        AccountManager.shared.exportAccount(target: target, name: inputAccountName) { success, msg in
                            isProcessing = false
                            loadFiles()
                            alertMsg = msg
                            showAlert = true
                        }
                    }
                    .padding()
                }
                .padding()
            }
            .alert(isPresented: $showAlert) {
                Alert(title: Text("提示"), message: Text(alertMsg), dismissButton: .default(Text("确定")))
            }
            .onAppear {
                reloadAllApps()
                loadFiles()
            }
        }
    }

    func reloadAllApps() {
        self.allApps = AccountManager.shared.scanAllInstalledApps()
        if selectedTarget == nil {
            // 默认优先选中第一个包含暗黑/暴雪的应用
            selectedTarget = allApps.first(where: {
                $0.displayName.contains("暗黑") ||
                $0.bundleID.lowercased().contains("diablo") ||
                $0.bundleID.lowercased().contains("blizzard")
            }) ?? allApps.first
        }
    }

    func loadFiles() {
        let dir = AccountManager.shared.storageDir
        let items = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        self.profileList = items.filter { $0.pathExtension == "lrj" }.map { url in
            let res = try? url.resourceValues(forKeys: [.fileSizeKey])
            let sizeBytes = res?.fileSize ?? 0
            let sizeMB = String(format: "%.2f MB", Double(sizeBytes) / 1024.0 / 1024.0)
            return ProfileItem(name: url.lastPathComponent, size: sizeMB, fileURL: url)
        }
    }
}
