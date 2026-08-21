import SwiftUI

struct ProfileItem: Identifiable {
    let id = UUID()
    let name: String
    let size: String
    let fileURL: URL
}

struct ContentView: View {
    @State private var instances: [AppTarget] = []
    @State private var selectedInstance: AppTarget? = nil
    @State private var profileList: [ProfileItem] = []
    @State private var activeFileName: String = ""
    @State private var alertMsg = ""
    @State private var showAlert = false
    @State private var inputAccountName = ""
    @State private var showInputDialog = false

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // 顶部多开分身选择器
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("目标分身:")
                            .font(.subheadline)
                            .bold()

                        if instances.isEmpty {
                            Text("未扫描到暗黑破坏神分身")
                                .foregroundColor(.red)
                                .font(.caption)
                        } else {
                            Picker("选择分身", selection: $selectedInstance) {
                                ForEach(instances, id: \.self) { app in
                                    Text("\(app.displayName) (\(app.bundleID))").tag(Optional(app))
                                }
                            }
                            .pickerStyle(MenuPickerStyle())
                        }

                        Spacer()

                        Button(action: refreshTargets) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 14))
                        }
                    }
                }
                .padding()
                .background(Color(UIColor.secondarySystemBackground))

                // 分割标签栏
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
                                    guard let target = selectedInstance else {
                                        alertMsg = "请先选择目标分身"
                                        showAlert = true
                                        return
                                    }
                                    AccountManager.shared.applyAccount(target: target, fileURL: item.fileURL) { success, msg in
                                        if success { activeFileName = item.name }
                                        alertMsg = msg
                                        showAlert = true
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .font(.caption)
                                .cornerRadius(4)

                                Button("删除") {
                                    try? FileManager.default.removeItem(at: item.fileURL)
                                    loadFiles()
                                }
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

                // 底部导出当前选定分身账号
                Button(action: {
                    if selectedInstance == nil {
                        alertMsg = "未选择任何分身"
                        showAlert = true
                    } else {
                        showInputDialog = true
                    }
                }) {
                    Text(selectedInstance == nil ? "请选择分身" : "备份当前 [\(selectedInstance!.displayName)] 数据")
                        .bold()
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(selectedInstance == nil ? Color.gray : Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .disabled(selectedInstance == nil)
                .padding()
            }
            .navigationTitle("账号数据管理")
            .onAppear {
                refreshTargets()
                loadFiles()
            }
            .alert(isPresented: $showAlert) {
                Alert(title: Text("提示"), message: Text(alertMsg), dismissButton: .default(Text("确定")))
            }
            .sheet(isPresented: $showInputDialog) {
                VStack(spacing: 20) {
                    Text("输入备份文件名").font(.headline)
                    TextField("例如: 暗黑破坏神(787)", text: $inputAccountName)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .padding()
                    Button("立即导出") {
                        showInputDialog = false
                        guard let target = selectedInstance, !inputAccountName.isEmpty else { return }
                        AccountManager.shared.exportAccount(target: target, name: inputAccountName) { success, msg in
                            loadFiles()
                            alertMsg = msg
                            showAlert = true
                        }
                    }
                    .padding()
                }
                .padding()
            }
        }
    }

    func refreshTargets() {
        self.instances = AccountManager.shared.scanInstalledInstances()
        if self.selectedInstance == nil || !self.instances.contains(where: { $0.id == self.selectedInstance?.id }) {
            self.selectedInstance = self.instances.first
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
