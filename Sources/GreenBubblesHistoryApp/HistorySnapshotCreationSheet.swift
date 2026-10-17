import AppKit
import Darwin
import Foundation
import GreenBubblesHistory
import SwiftUI

private enum SnapshotCreationPhase {
  case setup
  case generatingRecoveryKit
  case confirmRecoveryWords
  case creatingSnapshot
  case completed
  case failed
}

private enum SnapshotConvenienceMode: String, CaseIterable, Identifiable {
  case keychain
  case hiddenFile
  case none

  var id: String { rawValue }

  var title: String {
    switch self {
    case .keychain: "本机钥匙串"
    case .hiddenFile: "仅本人可读的隐藏文件"
    case .none: "不启用"
    }
  }
}

@MainActor
struct HistorySnapshotCreationSheet: View {
  @Bindable var model: HistoryBrowserModel
  @Environment(\.dismiss) private var dismiss

  @State private var phase: SnapshotCreationPhase = .setup
  @State private var outputPath = ""
  @State private var recoveryKitPath = ""
  @State private var hiddenCredentialPath = ""
  @State private var sourceAccess: HistorySnapshotSourceAccess = .encryptedWeChat
  @State private var stableCapture = false
  @State private var sourceKey = ""
  @State private var addsPassphrase = false
  @State private var snapshotPassphrase = ""
  @State private var snapshotPassphraseConfirmation = ""
  @State private var convenienceMode: SnapshotConvenienceMode = .keychain
  @State private var recoveryKit: HistorySnapshotRecoveryKit?
  @State private var challenge: HistorySnapshotWordChallenge?
  @State private var challengeResponses: [Int: String] = [:]
  @State private var confirmsIndependentCopy = false
  @State private var result: HistorySnapshotCreationResult?
  @State private var keychainStored = false
  @State private var completionWarning: String?
  @State private var errorMessage: String?
  @State private var operationTask: Task<Void, Never>?
  @State private var transientCredentialDirectory: URL?

  private let client = HistorySnapshotCreationClient()
  private let keychain = SnapshotKeychainStore()

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      header
      Divider()
      Group {
        switch phase {
        case .setup:
          setupView
        case .generatingRecoveryKit:
          progressView(
            title: "正在生成恢复词…",
            detail:
              "正在生成 24 个恢复词，并保存到你选择的私有文件中。"
          )
        case .confirmRecoveryWords:
          recoveryConfirmationView
        case .creatingSnapshot:
          progressView(
            title: "正在创建加密备份…",
            detail:
              "正在直接复制并加密聊天记录，不会生成明文数据库临时文件。"
          )
        case .completed:
          completionView
        case .failed:
          failureView
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    .padding(24)
    .onAppear(perform: prepareSuggestedPaths)
    .onChange(of: sourceAccess) { _, mode in
      if mode == .decryptedSQLite { sourceKey = "" }
      errorMessage = nil
    }
    .onChange(of: addsPassphrase) { _, enabled in
      if !enabled {
        snapshotPassphrase = ""
        snapshotPassphraseConfirmation = ""
      }
      errorMessage = nil
    }
    .onChange(of: convenienceMode) { _, _ in errorMessage = nil }
    .onDisappear {
      guard !isBusy else { return }
      clearDisplayedSecrets()
      removeTransientCredentialDirectory()
    }
    .interactiveDismissDisabled(isBusy)
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 5) {
      Text("创建可恢复的加密备份")
        .font(.title2.weight(.semibold))
      Text(
        "将微信记录保存为独立的加密备份。以后即使换电脑或无法登录微信，也可用恢复词打开。"
      )
      .foregroundStyle(.secondary)
    }
  }

  private var setupView: some View {
    VStack(spacing: 16) {
      Form {
        Section("本机备份工具") {
          pathField(
            title: "读取工具",
            text: $model.liveExecutablePath,
            actionTitle: "选择…",
            action: chooseExecutable
          )
        }

        Section("原始记录") {
          Picker("记录类型", selection: $sourceAccess) {
            ForEach(HistorySnapshotSourceAccess.allCases, id: \.rawValue) { mode in
              Text(mode.displayName).tag(mode)
            }
          }
          pathField(
            title: "原始记录文件夹",
            text: $model.directSourcePath,
            actionTitle: "选择…",
            action: chooseSource
          )
          Toggle("选择的是已完整采集、不会再变化的副本", isOn: $stableCapture)
          Text(
            stableCapture
              ? "备份前后都会核对采集清单和文件完整性。"
              : "以只读方式逐个读取数据库。各数据库内部保持一致，但可能对应略有不同的时间点。"
          )
          .font(.caption)
          .foregroundStyle(.secondary)
          if sourceAccess == .encryptedWeChat {
            SecureField("微信数据库密钥", text: $sourceKey)
              .textContentType(.password)
            Text("密钥仅通过本机安全输入通道使用，此备份操作不会保存密钥。")
              .font(.caption)
              .foregroundStyle(.secondary)
          } else {
            Label(
              "无需源密钥。仅在确认数据库已经解密时使用此选项。",
              systemImage: "exclamationmark.shield"
            )
            .font(.caption)
            .foregroundStyle(.orange)
          }
        }

        Section("备份保存位置") {
          pathField(
            title: "新备份文件夹",
            text: $outputPath,
            actionTitle: "选择…",
            action: chooseOutput
          )
          pathField(
            title: "新恢复词文件",
            text: $recoveryKitPath,
            actionTitle: "选择…",
            action: chooseRecoveryKitOutput
          )
          Label(
            "先保存恢复词，再开始备份。即使取消或失败，恢复词文件也会保留。请另外备份一份，避免与聊天记录一起丢失。",
            systemImage: "key.viewfinder"
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }

        Section("快捷解锁（可选）") {
          Picker("在本机保存解锁方式", selection: $convenienceMode) {
            ForEach(SnapshotConvenienceMode.allCases) { mode in
              Text(mode.title).tag(mode)
            }
          }
          if convenienceMode == .keychain {
            Text(
              "适合日常使用。快捷凭据只在这台电脑解锁后可用。仍须另存 24 个恢复词，供换机或丢失凭据时恢复。"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
          } else if convenienceMode == .hiddenFile {
            pathField(
              title: "新建隐藏解锁文件",
              text: $hiddenCredentialPath,
              actionTitle: "选择…",
              action: chooseHiddenCredentialOutput
            )
            Text(
              "隐藏文件仅本人可读，用于快捷解锁。删除它不会删除备份，之后仍可用恢复词打开。"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
          } else {
            Text("以后使用备份密码（如已设置）或恢复词文件打开。")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }

        Section("备份密码（可选）") {
          Toggle("另外设置一个备份密码", isOn: $addsPassphrase)
          if addsPassphrase {
            SecureField("备份解锁密码", text: $snapshotPassphrase)
              .textContentType(.newPassword)
            SecureField("再次输入备份密码", text: $snapshotPassphraseConfirmation)
              .textContentType(.newPassword)
            Text(
              "密码经过加密派生处理，不会保存到普通设置。即使设置了密码，也必须保管好 24 个恢复词。"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
          }
        }
      }
      .formStyle(.grouped)

      inlineError

      HStack {
        Button("取消") {
          clearDisplayedSecrets()
          dismiss()
        }
        .keyboardShortcut(.cancelAction)
        Spacer()
        Button("生成恢复词", action: startRecoveryKitCreation)
          .buttonStyle(HistoryActionStyle(prominent: true))
          .keyboardShortcut(.defaultAction)
      }
    }
  }

  private var recoveryConfirmationView: some View {
    VStack(alignment: .leading, spacing: 16) {
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          Label(
            "开始备份前，请按顺序保存这 24 个恢复词",
            systemImage: "exclamationmark.triangle.fill"
          )
          .font(.title3.weight(.semibold))
          .foregroundStyle(.orange)

          Text(
            "这些恢复词仅用于本应用的聊天备份，不可用作数字货币钱包助记词。它们已经保存到下方的私有文件中，请再另存一份。"
          )
          .foregroundStyle(.secondary)

          if let recoveryKit {
            Text(recoveryKit.url.path)
              .font(.caption.monospaced())
              .textSelection(.enabled)
              .padding(10)
              .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))

            LazyVGrid(
              columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 4),
              alignment: .leading,
              spacing: 10
            ) {
              ForEach(Array(recoveryKit.words.enumerated()), id: \.offset) { index, word in
                HStack(spacing: 6) {
                  Text("\(index + 1).")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                  Text(word)
                    .fontWeight(.medium)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
              }
            }
          }

          Divider()
          Text("填写以下四个位置的恢复词，确认已正确保存")
            .font(.headline)
          if let challenge {
            HStack(alignment: .top, spacing: 12) {
              ForEach(challenge.zeroBasedPositions, id: \.self) { position in
                VStack(alignment: .leading, spacing: 5) {
                  Text("第 \(position + 1) 个词")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                  TextField("恢复词", text: challengeBinding(position))
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 120)
                }
              }
            }
          }

          Toggle(
            "我已另存完整的 24 个恢复词，并了解本机快捷解锁不能代替恢复词备份。",
            isOn: $confirmsIndependentCopy
          )
          inlineError
        }
      }

      HStack {
        Button("取消并保留恢复词文件") {
          clearDisplayedSecrets()
          dismiss()
        }
        .keyboardShortcut(.cancelAction)
        Spacer()
        Button("确认恢复词并创建备份", action: startSnapshotCreation)
          .buttonStyle(HistoryActionStyle(prominent: true))
          .keyboardShortcut(.defaultAction)
      }
    }
  }

  private func progressView(title: String, detail: String) -> some View {
    VStack(spacing: 18) {
      Spacer()
      ProgressView()
        .controlSize(.large)
      Text(title)
        .font(.title2.weight(.semibold))
      Text(detail)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: 620)
      if phase == .creatingSnapshot {
        Label(
          "恢复词文件已保存，停止备份也不会删除它。",
          systemImage: "checkmark.shield"
        )
        .font(.callout)
        .foregroundStyle(.green)
      }
      Button(phase == .creatingSnapshot ? "停止备份" : "取消") {
        operationTask?.cancel()
      }
      .keyboardShortcut(.cancelAction)
      Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var completionView: some View {
    VStack(alignment: .leading, spacing: 18) {
      Label("加密备份已创建", systemImage: "checkmark.seal.fill")
        .font(.title2.weight(.semibold))
        .foregroundStyle(.green)
      if let result {
        GroupBox("检查结果") {
          VStack(alignment: .leading, spacing: 9) {
            LabeledContent("数据库", value: result.databaseCount.formatted())
            LabeledContent(
              "无需微信原密钥即可恢复", value: result.recoveryVerified ? "已验证" : "否")
            LabeledContent("独立加密", value: "使用全新的独立密钥加密")
            LabeledContent("换机恢复", value: "24 个恢复词")
            LabeledContent("恢复词文件", value: recoveryKitPath)
            LabeledContent("本机快捷解锁", value: completionConvenienceDescription)
            LabeledContent(
              "备份密码", value: result.hasPassphrase ? "已设置" : "未设置"
            )
          }
          .padding(6)
        }
        Text(
          "恢复词已从界面隐藏。请妥善保管恢复词文件及其备份，以便在微信或原密钥丢失后找回记录。"
        )
        .foregroundStyle(.secondary)
      }
      if let completionWarning {
        Label(completionWarning, systemImage: "exclamationmark.triangle.fill")
          .foregroundStyle(.orange)
          .textSelection(.enabled)
      }
      Spacer()
      HStack {
        Spacer()
        Button("完成") { dismiss() }
          .buttonStyle(HistoryActionStyle(prominent: true))
          .keyboardShortcut(.defaultAction)
      }
    }
  }

  private var failureView: some View {
    VStack(alignment: .leading, spacing: 18) {
      Label("备份未完成", systemImage: "xmark.octagon.fill")
        .font(.title2.weight(.semibold))
        .foregroundStyle(.red)
      if let errorMessage {
        Text(errorMessage)
          .textSelection(.enabled)
      }
      GroupBox {
        VStack(alignment: .leading, spacing: 8) {
          Label("恢复词文件已保留", systemImage: "key.viewfinder")
            .foregroundStyle(.green)
          Text(recoveryKitPath)
            .font(.caption.monospaced())
            .textSelection(.enabled)
          Text(
            "本次输入的密钥、密码和恢复词已从向导中清除。请更换保存位置后重试。"
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }
        .padding(6)
      }
      Spacer()
      HStack {
        Spacer()
        Button("关闭") { dismiss() }
          .buttonStyle(HistoryActionStyle(prominent: true))
          .keyboardShortcut(.defaultAction)
      }
    }
  }

  @ViewBuilder
  private var inlineError: some View {
    if let errorMessage {
      Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
        .font(.callout)
        .foregroundStyle(.red)
        .textSelection(.enabled)
    }
  }

  private var isBusy: Bool {
    phase == .generatingRecoveryKit || phase == .creatingSnapshot
  }

  private var completionConvenienceDescription: String {
    switch convenienceMode {
    case .keychain:
      keychainStored
        ? "本机钥匙串（仅此电脑可用）"
        : "钥匙串不可用，请使用恢复词或备份密码"
    case .hiddenFile: "仅本人可读的隐藏解锁文件"
    case .none: "不启用"
    }
  }

  private func pathField(
    title: String,
    text: Binding<String>,
    actionTitle: String,
    action: @escaping () -> Void
  ) -> some View {
    HStack {
      TextField(title, text: text)
        .textFieldStyle(.roundedBorder)
      Button(actionTitle, action: action)
    }
  }

  private func challengeBinding(_ position: Int) -> Binding<String> {
    Binding(
      get: { challengeResponses[position] ?? "" },
      set: { challengeResponses[position] = $0.lowercased() }
    )
  }

  private func prepareSuggestedPaths() {
    guard outputPath.isEmpty || recoveryKitPath.isEmpty || hiddenCredentialPath.isEmpty else {
      return
    }
    do {
      let suggestions = try SnapshotWizardStorage.suggestedPaths()
      if outputPath.isEmpty { outputPath = suggestions.snapshot.path }
      if recoveryKitPath.isEmpty { recoveryKitPath = suggestions.recoveryKit.path }
      if hiddenCredentialPath.isEmpty {
        hiddenCredentialPath = suggestions.hiddenCredential.path
      }
    } catch {
      errorMessage =
        "无法创建私有的默认文件夹，请手动选择仅本人可访问的位置。"
    }
  }

  private func startRecoveryKitCreation() {
    guard validateSetup() else { return }
    errorMessage = nil
    phase = .generatingRecoveryKit
    let executableURL = URL(fileURLWithPath: trimmed(model.liveExecutablePath))
    let kitURL = URL(fileURLWithPath: trimmed(recoveryKitPath))
    operationTask = Task {
      do {
        let created = try await client.createRecoveryKit(
          executableURL: executableURL,
          outputURL: kitURL
        )
        try Task.checkCancellation()
        recoveryKit = created
        challenge = try HistorySnapshotWordChallenge.random()
        challengeResponses = [:]
        confirmsIndependentCopy = false
        phase = .confirmRecoveryWords
      } catch is CancellationError {
        errorMessage =
          "已取消生成恢复词。已生成的文件会保留，请选择新的文件位置后重试。"
        phase = .setup
      } catch {
        errorMessage = localizedSnapshotError(error)
        phase = .setup
      }
      operationTask = nil
    }
  }

  private func startSnapshotCreation() {
    guard let recoveryKit, let challenge else {
      errorMessage = "请先生成恢复词并完成确认。"
      return
    }
    guard confirmsIndependentCopy else {
      errorMessage = "请确认已在其他安全位置保存全部 24 个恢复词。"
      return
    }
    guard challenge.accepts(responses: challengeResponses, words: recoveryKit.words) else {
      errorMessage = "填写的恢复词与对应位置不一致，请检查后重试。"
      return
    }

    let executableURL = URL(fileURLWithPath: trimmed(model.liveExecutablePath))
    let sourceURL = URL(fileURLWithPath: trimmed(model.directSourcePath), isDirectory: true)
    let snapshotURL = URL(fileURLWithPath: trimmed(outputPath), isDirectory: true)
    let hiddenURL = URL(fileURLWithPath: trimmed(hiddenCredentialPath))
    let requestedConvenience = convenienceMode
    let requestedSourceAccess = sourceAccess
    let requestedStableCapture = stableCapture
    let sourceSecretInput = Array(sourceKey.utf8)
    let snapshotSecretInput = addsPassphrase ? Array(snapshotPassphrase.utf8) : []

    clearDisplayedSecrets()
    errorMessage = nil
    phase = .creatingSnapshot
    operationTask = Task {
      var sourceSecret = sourceSecretInput
      var snapshotSecret = snapshotSecretInput
      var localCredentialData = Data()
      var localCredentialURL: URL?
      var createdHiddenCredential = false
      var snapshotPublished = false
      defer {
        sourceSecret.resetBytes(in: 0..<sourceSecret.count)
        snapshotSecret.resetBytes(in: 0..<snapshotSecret.count)
        localCredentialData.resetBytes(in: 0..<localCredentialData.count)
        removeTransientCredentialDirectory()
      }
      do {
        switch requestedConvenience {
        case .keychain:
          let directory = try SnapshotWizardStorage.makeTemporaryCredentialDirectory()
          transientCredentialDirectory = directory
          let credentialURL = directory.appending(path: ".snapshot-local-unlock")
          localCredentialData = try await client.createLocalCredential(
            executableURL: executableURL,
            outputURL: credentialURL
          )
          localCredentialURL = credentialURL
        case .hiddenFile:
          localCredentialData = try await client.createLocalCredential(
            executableURL: executableURL,
            outputURL: hiddenURL
          )
          localCredentialURL = hiddenURL
          createdHiddenCredential = true
        case .none:
          break
        }

        let request = HistorySnapshotCreationRequest(
          executableURL: executableURL,
          sourceURL: sourceURL,
          outputURL: snapshotURL,
          recoveryKit: recoveryKit,
          localCredentialURL: localCredentialURL,
          sourceAccess: requestedSourceAccess,
          stableCapture: requestedStableCapture
        )
        let created = try await client.createSnapshot(
          request: request,
          sourceKeyUTF8: sourceSecret,
          snapshotPassphraseUTF8: snapshotSecret
        )
        snapshotPublished = true

        var savedToKeychain = false
        var warning: String?
        if requestedConvenience == .keychain {
          do {
            try keychain.save(localCredentialData, snapshotID: created.snapshotID)
            savedToKeychain = true
          } catch {
            warning =
              "备份已完成，但钥匙串未能保存快捷解锁凭据。仍可使用 24 个恢复词\(created.hasPassphrase ? "或备份密码" : "")打开。"
          }
        }

        keychainStored = savedToKeychain
        completionWarning = warning
        result = created
        model.rememberCreatedSnapshot(
          created,
          keychainProtected: savedToKeychain,
          hiddenCredentialURL: requestedConvenience == .hiddenFile ? hiddenURL : nil,
          recoveryKitURL: recoveryKit.url,
          passphraseProtected: created.hasPassphrase
        )
        phase = .completed
      } catch is CancellationError {
        if createdHiddenCredential && !snapshotPublished {
          try? FileManager.default.removeItem(at: hiddenURL)
        }
        errorMessage =
          "备份已停止，未完成的临时数据已清理。"
        phase = .failed
      } catch {
        if createdHiddenCredential && !snapshotPublished {
          try? FileManager.default.removeItem(at: hiddenURL)
        }
        errorMessage = localizedSnapshotError(error)
        phase = .failed
      }
      operationTask = nil
    }
  }

  private func validateSetup() -> Bool {
    let executable = trimmed(model.liveExecutablePath)
    let source = trimmed(model.directSourcePath)
    let output = trimmed(outputPath)
    let kit = trimmed(recoveryKitPath)
    guard !executable.isEmpty, !source.isEmpty, !output.isEmpty, !kit.isEmpty else {
      errorMessage = "请选择读取工具、原始记录、新备份文件夹和恢复词文件位置。"
      return false
    }
    let pathSet = Set(
      [source, output, kit]
        + (convenienceMode == .hiddenFile ? [trimmed(hiddenCredentialPath)] : []))
    let expectedPathCount = convenienceMode == .hiddenFile ? 4 : 3
    guard pathSet.count == expectedPathCount else {
      errorMessage = "原始记录、备份、恢复词和解锁文件必须使用不同的保存位置。"
      return false
    }
    if sourceAccess == .encryptedWeChat {
      let key = Array(sourceKey.utf8)
      let isRaw = key.count == 32
      let isHex = key.count == 64 && key.allSatisfy(isWizardHexadecimal)
      guard isRaw || isHex else {
        errorMessage = "请输入 32 字节或 64 位十六进制格式的微信数据库密钥。"
        return false
      }
    }
    if convenienceMode == .hiddenFile, trimmed(hiddenCredentialPath).isEmpty {
      errorMessage = "请选择新的私有隐藏解锁文件位置。"
      return false
    }
    if addsPassphrase {
      let bytes = Array(snapshotPassphrase.utf8)
      guard snapshotPassphrase == snapshotPassphraseConfirmation,
        (12...1_024).contains(bytes.count), !bytes.contains(0), !bytes.contains(10),
        !bytes.contains(13)
      else {
        errorMessage =
          "两次密码须一致，长度为 12–1,024 字节，不能包含换行。"
        return false
      }
    }
    return true
  }

  private func clearDisplayedSecrets() {
    sourceKey = ""
    snapshotPassphrase = ""
    snapshotPassphraseConfirmation = ""
    if var words = recoveryKit?.words {
      for index in words.indices { words[index] = "" }
    }
    recoveryKit = nil
    challenge = nil
    challengeResponses = [:]
    confirmsIndependentCopy = false
  }

  private func removeTransientCredentialDirectory() {
    guard let directory = transientCredentialDirectory else { return }
    try? FileManager.default.removeItem(at: directory)
    transientCredentialDirectory = nil
  }

  private func chooseExecutable() {
    let panel = NSOpenPanel()
    panel.title = "选择本机读取工具"
    panel.prompt = "选择工具"
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    panel.resolvesAliases = false
    if panel.runModal() == .OK, let url = panel.url {
      model.liveExecutablePath = url.path
    }
  }

  private func chooseSource() {
    let panel = NSOpenPanel()
    panel.title = "选择微信记录文件夹或完整采集副本"
    panel.prompt = "选择记录来源"
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.resolvesAliases = false
    if panel.runModal() == .OK, let url = panel.url {
      model.directSourcePath = url.path
    }
  }

  private func chooseOutput() {
    chooseNewPath(
      title: "选择新备份的保存文件夹",
      prompt: "选择备份位置",
      currentPath: outputPath
    ) { outputPath = $0 }
  }

  private func chooseRecoveryKitOutput() {
    chooseNewPath(
      title: "选择新恢复词文件的保存位置",
      prompt: "选择恢复词文件",
      currentPath: recoveryKitPath
    ) { recoveryKitPath = $0 }
  }

  private func chooseHiddenCredentialOutput() {
    chooseNewPath(
      title: "选择新隐藏解锁文件的保存位置",
      prompt: "选择隐藏文件",
      currentPath: hiddenCredentialPath,
      showsHiddenFiles: true
    ) { hiddenCredentialPath = $0 }
  }

  private func chooseNewPath(
    title: String,
    prompt: String,
    currentPath: String,
    showsHiddenFiles: Bool = false,
    assign: (String) -> Void
  ) {
    let current = URL(fileURLWithPath: currentPath)
    let panel = NSSavePanel()
    panel.title = title
    panel.prompt = prompt
    panel.canCreateDirectories = true
    panel.showsHiddenFiles = showsHiddenFiles
    panel.directoryURL = current.deletingLastPathComponent()
    panel.nameFieldStringValue = current.lastPathComponent
    if panel.runModal() == .OK, let url = panel.url { assign(url.path) }
  }

  private func localizedSnapshotError(_ error: Error) -> String {
    historyUserError(error)
  }

  private func trimmed(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

private struct SnapshotWizardSuggestedPaths {
  let snapshot: URL
  let recoveryKit: URL
  let hiddenCredential: URL
}

private enum SnapshotWizardStorage {
  static func suggestedPaths() throws -> SnapshotWizardSuggestedPaths {
    let support = try FileManager.default.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )
    let base = support.appending(path: "GreenBubbles", directoryHint: .isDirectory)
    let snapshots = base.appending(path: "Recoverable Snapshots", directoryHint: .isDirectory)
    let recovery = base.appending(path: "Recovery Kits", directoryHint: .isDirectory)
    let credentials = base.appending(path: "Local Unlocks", directoryHint: .isDirectory)
    for directory in [base, snapshots, recovery, credentials] {
      try ensurePrivateDirectory(directory)
    }
    let identifier = UUID().uuidString.lowercased()
    return SnapshotWizardSuggestedPaths(
      snapshot: snapshots.appending(path: "snapshot-\(identifier)"),
      recoveryKit: recovery.appending(path: "recovery-\(identifier).txt"),
      hiddenCredential: credentials.appending(path: ".snapshot-unlock-\(identifier)")
    )
  }

  static func makeTemporaryCredentialDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appending(
      path: "greenbubbles-snapshot-create-\(UUID().uuidString)",
      directoryHint: .isDirectory
    )
    try ensurePrivateDirectory(directory, mustBeNew: true)
    return directory
  }

  private static func ensurePrivateDirectory(_ url: URL, mustBeNew: Bool = false) throws {
    if mkdir(url.path, S_IRWXU) != 0 {
      guard !mustBeNew, errno == EEXIST else {
        throw HistorySnapshotCreationError.unsafeProtector
      }
    }
    var metadata = stat()
    guard lstat(url.path, &metadata) == 0, metadata.st_mode & S_IFMT == S_IFDIR,
      metadata.st_uid == getuid(), chmod(url.path, S_IRWXU) == 0
    else { throw HistorySnapshotCreationError.unsafeProtector }
  }
}

private func isWizardHexadecimal(_ byte: UInt8) -> Bool {
  (byte >= 48 && byte <= 57) || (byte >= 65 && byte <= 70)
    || (byte >= 97 && byte <= 102)
}
