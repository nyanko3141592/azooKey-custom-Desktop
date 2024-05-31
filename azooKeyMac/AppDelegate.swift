//
//  AppDelegate.swift
//  AppDelegate
//
//  Created by ensan on 2021/09/06.
//

import Cocoa
import SwiftUI
import InputMethodKit
import KanaKanjiConverterModuleWithDefaultDictionary

// Necessary to launch this app
class NSManualApplication: NSApplication {
    let appDelegate = AppDelegate()

    override init() {
        super.init()
        self.delegate = appDelegate
    }

    required init?(coder: NSCoder) {
        // No need for implementation
        fatalError("init(coder:) has not been implemented")
    }
}

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    var server = IMKServer()
    var candidatesWindow = IMKCandidates()
    weak var configWindow: NSWindow?
    var configWindowController: NSWindowController?
    @MainActor var kanaKanjiConverter = KanaKanjiConverter()

    // 現在アクティブなアプリケーションの名前を保持する変数
    var activeApplicationName: String = ""
    // Slackアプリケーションを表すAXUIElement
    var slackApp: AXUIElement!

    func openConfigWindow() {
        if let configWindow {
            // Show the window
            configWindow.level = .modalPanel
            configWindow.makeKeyAndOrderFront(nil)
        } else {
            // Create a new window
            let configWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                styleMask: [.titled, .closable, .resizable, .borderless],
                backing: .buffered,
                defer: false
            )
            // Set the window title
            configWindow.title = "設定"
            configWindow.contentViewController = NSHostingController(rootView: ConfigWindow())
            // Keep window with in a controller
            self.configWindowController = NSWindowController(window: configWindow)
            // Show the window
            configWindow.level = .modalPanel
            configWindow.makeKeyAndOrderFront(nil)
            // Assign the new window to the property to keep it in memory
            self.configWindow = configWindow
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Insert code here to initialize your application
        self.server = IMKServer(name: Bundle.main.infoDictionary?["InputMethodConnectionName"] as? String, bundleIdentifier: Bundle.main.bundleIdentifier)
        self.candidatesWindow = IMKCandidates(server: server, panelType: kIMKSingleColumnScrollingCandidatePanel, styleType: kIMKMain)
        NSLog("tried connection")

        // Accessibility API Permission Request
        // AXIsProcessTrustedWithOptionsのオプションを設定（アクセス許可のプロンプトを表示）
        let trustedCheckOptionPrompt = kAXTrustedCheckOptionPrompt.takeRetainedValue() as NSString
        let options = [trustedCheckOptionPrompt: true] as CFDictionary
        if AXIsProcessTrustedWithOptions(options) {
            // アクセス許可が与えられている場合、セットアップとアクティブアプリのモニタリングを開始
            setup()
            monitorActiveApplication()
        } else {
            // アクセス許可が与えられていない場合、許可が与えられるまで待つ
            waitPermissionGranted {
                self.setup()
                self.monitorActiveApplication()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Insert code here to tear down your application
    }

    // セットアップメソッド
    private func setup() {
        // Slackアプリケーションを取得し、変数にセット
        if let slackApp = getSlackApplication() {
            self.slackApp = slackApp
        } else {
            // Slackが起動していない場合のエラーメッセージ
            NSLog("Slack is not running.")
        }
    }

    // SlackアプリケーションのAXUIElementを取得するメソッド
    private func getSlackApplication() -> AXUIElement? {
        let workspace = NSWorkspace.shared
        let apps = workspace.runningApplications
        for app in apps {
            // アプリケーションの名前が「Slack」の場合、そのプロセスIDを使ってAXUIElementを作成
            if app.localizedName == "Slack" {
                return AXUIElementCreateApplication(app.processIdentifier)
            }
        }
        return nil
    }

    // Slackメッセージを取得するメソッド
    private func fetchSlackMessages(from app: AXUIElement) {
        NSLog("Attempting to fetch Slack messages...")
        var value: AnyObject?
        // Slackアプリのウィンドウを取得 Fail to get Slack windows
        let result = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value)
        NSLog("Result: \(result)")
        // resultが成功で、valueが[AXUIElement]型である場合
        if result == .success, let windows = value as? [AXUIElement] {
            NSLog("Found \(windows.count) windows.")
            for window in windows {
                // 各ウィンドウからメッセージを抽出
                extractMessagesFromWindow(window)
            }
        } else {
            NSLog("Could not retrieve Slack windows.")
        }
    }

    // ウィンドウからメッセージを抽出するメソッド
    private func extractMessagesFromWindow(_ window: AXUIElement) {
        var value: AnyObject?
        // ウィンドウの子要素を取得
        let result = AXUIElementCopyAttributeValue(window, kAXChildrenAttribute as CFString, &value)
        if result == .success, let children = value as? [AXUIElement] {
            for child in children {
                // 各子要素からメッセージを抽出
                extractMessagesFromElement(child)
            }
        } else {
            NSLog("Could not retrieve window children.")
        }
    }

    // 要素からメッセージを抽出するメソッド
    private func extractMessagesFromElement(_ element: AXUIElement) {
        var value: AnyObject?
        // 要素の役割を取得
        let result = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value)
        if result == .success, let role = value as? String {
            if role == kAXStaticTextRole as String {
                // 要素が静的テキストの場合、その値を取得
                var messageValue: AnyObject?
                let messageResult = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &messageValue)
                if messageResult == .success, let message = messageValue as? String {
                    NSLog("Message: \(message)")
                }
            } else {
                // 要素に子要素がある場合、それらを再帰的に処理
                var childValue: AnyObject?
                let childResult = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childValue)
                if childResult == .success, let children = childValue as? [AXUIElement] {
                    for child in children {
                        extractMessagesFromElement(child)
                    }
                }
            }
        }
    }

    // アクティブなアプリケーションをモニタリングするメソッド
    private func monitorActiveApplication() {
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            let workspace = NSWorkspace.shared
            if let activeApp = workspace.frontmostApplication {
                // アクティブアプリケーションが変わった場合、その名前を更新
                if self.activeApplicationName != activeApp.localizedName {
                    self.activeApplicationName = activeApp.localizedName ?? ""
                    NSLog("Active application: \(self.activeApplicationName)")
                    // アクティブアプリがSlackの場合、メッセージを取得
                    if self.activeApplicationName == "Slack" {
                        if let slackApp = self.slackApp {
                            self.fetchSlackMessages(from: slackApp)
                        }
                    }
                }
            }
        }
    }

    // アクセス許可が与えられるまで待つメソッド
    private func waitPermissionGranted(completion: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if AXIsProcessTrusted() {
                completion()
            } else {
                // 許可が与えられるまで再帰的に呼び出す
                self.waitPermissionGranted(completion: completion)
            }
        }
    }
}
