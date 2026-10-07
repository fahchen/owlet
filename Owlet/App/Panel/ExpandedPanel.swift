import SwiftUI
import SwiftData

struct ExpandedPanel: View {
    @AppStorage(SettingsStore.panelGlassEffectKey) private var glassEffect = PanelGlassEffect.contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var model: TextProcessingModel
    let replace: ((String) -> Void)?
    let copy: (String) -> Void
    let collection: CollectionAction?
    let openNotebook: (() -> Void)?
    let notice: PanelController.Notice?
    let recover: (PanelController.Notice) -> Void
    let retry: () -> Void
    let cancel: () -> Void
    let openSettings: () -> Void
    let close: () -> Void
    @State var learning = LearningModel()
    @AppStorage(SettingsStore.pinnedTargetKey) private var pinnedTarget = ""

    private var showsLearning: Bool {
        LearningRequest.from(model) != nil && (learning.isExpanded || learning.state != .idle)
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            HStack(alignment: .top, spacing: 0) {
                ScrollView {
                    ExpandedPanelContent(
                        model: model, notice: notice, recover: recover,
                        collection: collection, openNotebook: openNotebook, learning: learning,
                        showsSource: !showsLearning)
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(maxWidth: .infinity)
                if showsLearning, let collection, let request = LearningRequest.from(model) {
                    Divider()
                        .padding(.vertical, PanelMetrics.contentInset)
                    PanelLearningView(
                        learning: learning, request: request, collection: collection,
                        openNotebook: openNotebook
                    )
                    .modelContainer(collection.store.container)
                    .padding(PanelMetrics.contentInset)
                    .frame(width: PanelMetrics.width / 2)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .frame(height: showsLearning ? 295 : 257)
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                if model.state == .loading {
                    Button(action: cancel) { Label("取消处理", systemImage: "stop").foregroundStyle(.primary) }
                        .labelStyle(.iconOnly).buttonStyle(.glass(glassEffect.glass))
                }
                if showsLearning || LearningRequest.from(model) == nil || collection == nil {
                    Button(action: close) { Label("关闭", systemImage: "xmark").foregroundStyle(.primary) }
                        .labelStyle(.iconOnly).font(.system(size: 13, weight: .medium))
                        .buttonStyle(.glass(glassEffect.glass)).buttonBorderShape(.circle).controlSize(.extraLarge)
                        .buttonSizing(.flexible).frame(width: 36, height: 36)
                        .help("关闭浮窗")
                } else {
                    Button {
                        learning.isExpanded = true
                    } label: {
                        Label("学习", systemImage: "lamp.desk").foregroundStyle(.primary)
                    }
                    .labelStyle(.iconOnly).font(.system(size: 13, weight: .medium))
                    .buttonStyle(.glass(glassEffect.glass)).buttonBorderShape(.circle).controlSize(.extraLarge)
                    .buttonSizing(.flexible).frame(width: 36, height: 36)
                    .help("展开学习表达")
                }
                if case .success(let text) = model.state {
                    Button {
                        copy(text)
                    } label: {
                        Label("复制", systemImage: "document.on.document").foregroundStyle(.primary)
                    }
                    .labelStyle(.iconOnly).font(.system(size: 13, weight: .medium))
                    .buttonStyle(.glass(glassEffect.glass)).buttonBorderShape(.circle).controlSize(.extraLarge)
                    .buttonSizing(.flexible).frame(width: 36, height: 36)
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                    .help("复制结果 ⌘⇧C")
                }
            }
            .padding(.horizontal, PanelMetrics.contentInset)
            .padding(.bottom, PanelMetrics.contentInset)
        }
        .contextMenu {
            Picker("快捷操作", selection: $model.operation) {
                ForEach(Operation.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .onChange(of: model.operation) { _, _ in if canRetry { retry() } }
            .disabled(!canRetry)
            if model.operation == .translate {
                TargetLanguagePicker(text: model.input, pinnedTarget: $pinnedTarget)
                    .disabled(model.state == .loading)
            }
            Button("重新处理", systemImage: "arrow.clockwise", action: retry)
                .disabled(!canRetry)
            if case .success(let text) = model.state, let replace {
                Button("替换原选区") { replace(text) }
                    .keyboardShortcut(.return, modifiers: .command)
            }
            Button(action: close) { Label("关闭", systemImage: "xmark").foregroundStyle(.primary) }
            Button("设置", systemImage: "gearshape", action: openSettings)
        }
        .frame(width: PanelMetrics.width, height: showsLearning ? 295 : 257)
        .clipped()
        .glassEffect(glassEffect.glass, in: ButtonBorderShape.roundedRectangle)
        .animation(reduceMotion ? nil : .spring(duration: 0.36, bounce: 0.12), value: showsLearning)
        .background {
            if !showsLearning, let collection, let request = LearningRequest.from(model) {
                PanelLearningView(
                    learning: learning, request: request, collection: collection,
                    openNotebook: openNotebook, showsDisclosure: false
                )
                .modelContainer(collection.store.container)
                .hidden()
                .frame(width: 0, height: 0)
            }
        }
        .onChange(of: model.state) { _, state in
            if state == .loading { learning.reset() }
        }
        .onChange(of: pinnedTarget) { _, _ in
            learning.reset()
            if canRetry { retry() }
        }
    }

    private var canRetry: Bool {
        model.state != .loading && !model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
