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

    // Slack Connection
    let targetAppName: String = "Slack" // 監視対象のアプリケーション名
    var activeApplicationName: String = "" // 現在アクティブなアプリケーションの名前を保存する変数
    var slackApp: AXUIElement! // SlackアプリケーションのAXUIElementオブジェクト
    var observer: AXObserver? // AXObserverオブジェクト

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

        // アクセシビリティの権限を確認するためのオプションを設定
        let trustedCheckOptionPrompt = kAXTrustedCheckOptionPrompt.takeRetainedValue() as NSString
        let options = [trustedCheckOptionPrompt: true] as CFDictionary
        // アクセシビリティの権限が許可されているか確認
        if AXIsProcessTrustedWithOptions(options) {
            NSLog("Permission granted.")
            setup() // 権限がある場合、初期設定を行う
        } else {
            NSLog("Permission not granted.")
            // 権限がない場合、権限が許可されるまで待つ
            waitPermissionGranted {
                self.setup()
            }
        }
        // アクティブなアプリケーションが変更されたときの通知を登録
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(activeAppDidChange(_:)), name: NSWorkspace.didActivateApplicationNotification, object: nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Insert code here to tear down your application
    }

    // アクティブなアプリケーションが変更されたときに呼び出されるメソッド
    @objc func activeAppDidChange(_ notification: Notification) {
        if let activeApp = NSWorkspace.shared.frontmostApplication {
            activeApplicationName = activeApp.localizedName! // 新しいアクティブなアプリケーションの名前を取得
            NSLog("Active app: \(activeApplicationName)") // アクティブなアプリケーションの名前を出力
            if activeApplicationName == targetAppName {
                if let slackApp = slackApp {

                    fetchSlackMessages(from: slackApp) // Slackがアクティブになった場合、メッセージを取得
                }
            }
        }
    }

    // セットアップメソッド
    private func setup() {
        if let slackApp = getSlackApplication() {
            self.slackApp = slackApp // SlackアプリケーションのAXUIElementオブジェクトを保存
            startMonitoringSlack() // Slackの監視を開始
        } else {
            NSLog("Slack is not running.") // Slackが実行されていない場合のメッセージ
        }
    }

    // SlackアプリケーションのAXUIElementオブジェクトを取得するメソッド
    private func getSlackApplication() -> AXUIElement? {
        let workspace = NSWorkspace.shared
        let apps = workspace.runningApplications
        for app in apps {
            if app.localizedName == targetAppName{
                return AXUIElementCreateApplication(app.processIdentifier) // SlackアプリケーションのAXUIElementオブジェクトを返す
            }
        }
        return nil // Slackアプリケーションが見つからない場合はnilを返す
    }

    // Slackからメッセージを取得するメソッド
    private func fetchSlackMessages(from app: AXUIElement) {
        NSLog("Attempting to fetch Slack messages...") // メッセージ取得の試行を出力
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value)
        if result == .success, let windows = value as? [AXUIElement] {
            for window in windows {
                extractMessagesFromWindow(window) // 各ウィンドウからメッセージを抽出
            }
        } else {
            NSLog("Could not retrieve Slack windows.") // Slackウィンドウが取得できない場合のメッセージ
            LogAXUIElementState(of: slackApp)
        }
    }

    // ウィンドウからメッセージを抽出するメソッド
    private func extractMessagesFromWindow(_ window: AXUIElement) {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(window, kAXChildrenAttribute as CFString, &value)
        if result == .success, let children = value as? [AXUIElement] {
            for child in children {
                extractMessagesFromElement(child) // 各子要素からメッセージを抽出
            }
        } else {
            NSLog("Could not retrieve window children.") // ウィンドウの子要素が取得できない場合のメッセージ
        }
    }

    // 要素からメッセージを抽出するメソッド
    private func extractMessagesFromElement(_ element: AXUIElement) {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value)
        if result == .success, let role = value as? String {
            if role == kAXStaticTextRole as String {
                var messageValue: AnyObject?
                let messageResult = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &messageValue)
                if messageResult == .success, let message = messageValue as? String {
                    NSLog("Message: \(message)") // メッセージの出力
                }
            } else {
                var childValue: AnyObject?
                let childResult = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childValue)
                if childResult == .success, let children = childValue as? [AXUIElement] {
                    for child in children {
                        extractMessagesFromElement(child) // 各子要素から再帰的にメッセージを抽出
                    }
                }
            }
        }
    }

    private func startMonitoringSlack() {
        NSLog("Starting Slack monitoring...")
        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == targetAppName }) else {
            NSLog("\(self.targetAppName) is not running.") // Slackが実行されていない場合のメッセージ
            return
        }

        // FIXME: Failed to add AXObserver notification for Slack with error: -25204
        // SlackのWindow監視に失敗する
        // AXObserverの作成で用いるSlack WindowのAXUIElementが正常に取得できていない

        LogAXUIElementState(of: slackApp)

        var observer: AXObserver?
        AXObserverCreate(app.processIdentifier, { (observer, element, notification, refcon) in
            let delegate = Unmanaged<AppDelegate>.fromOpaque(refcon!).takeUnretainedValue()
            delegate.handleAXEvent(element: element, notification: notification as String) // アクセシビリティイベントのハンドリング
        }, &observer)


        if let observer = observer {
            let addNotificationResult = AXObserverAddNotification(observer, slackApp, kAXValueChangedNotification as CFString, UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()))
            if addNotificationResult == .success {
                NSLog("Successfully added AXObserver notification for Slack.")
            } else {
                NSLog("Failed to add AXObserver notification for Slack with error: \(addNotificationResult.rawValue)")
            }
            CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode)
            self.observer = observer // 監視オブジェクトを保存
        } else {
            NSLog("Failed to create AXObserver.")
        }
    }

    // アクセシビリティイベントをハンドリングするメソッド
    private func handleAXEvent(element: AXUIElement, notification: String) {
        if notification == kAXValueChangedNotification as String {
            fetchSlackMessages(from: slackApp) // AXValueChangedNotificationイベントが発生したときにメッセージを取得
        }
    }

    // アクセシビリティ権限が許可されるまで待つメソッド
    private func waitPermissionGranted(completion: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if AXIsProcessTrusted() {
                completion() // 権限が許可された場合、完了ハンドラを呼び出す
            } else {
                self.waitPermissionGranted(completion: completion) // 権限が許可されていない場合、再試行
            }
        }
    }
    
    func LogAXUIElementState(of app: AXUIElement) {
        var attributes: CFArray?
        let result = AXUIElementCopyAttributeNames(app, &attributes)

        if result == .success, let attributes = attributes as? [String] {
            for attribute in attributes {
                var value: AnyObject?
                let valueResult = AXUIElementCopyAttributeValue(app, attribute as CFString, &value)
                if valueResult == .success {
                    NSLog("Attribute: \(attribute), Value: \(String(describing: value))")
                } else {
                    NSLog("Attribute: \(attribute), Value: Error retrieving value")
                }
            }
        } else {
            NSLog("Error retrieving AXUIElement attributes")
        }
    }

}
