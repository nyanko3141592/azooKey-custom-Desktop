import SwiftUI
import AppKit

struct ConfigWindow: View {
    @ConfigState private var liveConversion = Config.LiveConversion()
    @ConfigState private var englishConversion = Config.EnglishConversion()
    @ConfigState private var typeBackSlash = Config.TypeBackSlash()
    @ConfigState private var openAiApiKey = Config.OpenAiApiKey()
    @ConfigState private var learning = Config.Learning()
    @ConfigState private var inferenceLimit = Config.ZenzaiInferenceLimit()
    @State private var isAccessibilityTrusted = AXIsProcessTrusted()

    var body: some View {
        VStack {
            Text("設定")
                .font(.title)
            Toggle("ライブ変換を有効化", isOn: $liveConversion)
            Toggle("英単語変換を有効化", isOn: $englishConversion)
            Toggle("円記号の代わりにバックスラッシュを入力", isOn: $typeBackSlash)
            TextField("OpenAI API Key", text: $openAiApiKey)
            Stepper("Zenzaiの推論上限: \(inferenceLimit.value)", value: $inferenceLimit, in: 0 ... 50)
            Picker("学習", selection: $learning) {
                Text("学習する").tag(Config.Learning.Value.inputAndOutput)
                Text("学習を停止").tag(Config.Learning.Value.onlyOutput)
                Text("学習を無視").tag(Config.Learning.Value.nothing)
            }

            if isAccessibilityTrusted {
                Text("アクセシビリティ権限が付与されています")
                    .foregroundColor(.green)
            } else {
                Text("アクセシビリティ権限がありません")
                    .foregroundColor(.red)
                Button(action: {
                    requestAccessibilityPermissions()
                }) {
                    Text("アクセシビリティ権限をリクエスト")
                        .padding(.top, 10)
                }
            }

            Button(action: {
                let url = URL(
                    string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
                )!
                NSWorkspace.shared.open(url)
            }) {
                Text("アクセシビリティ設定を開く")
                    .padding(10)
            }
        }
        .frame(width: 400, height: 300)
        .onAppear(perform: checkAccessibilityPermissions)
    }

    private func requestAccessibilityPermissions() {
        NSLog("Request Permission to Access")
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as NSString: true]
        AXIsProcessTrustedWithOptions(options)
        checkAccessibilityPermissions()
    }

    private func checkAccessibilityPermissions() {
        isAccessibilityTrusted = AXIsProcessTrusted()
    }
}
