import Flutter
import Foundation
import Security
import StoreKit
import UIKit
import WidgetKit

/// 앱(Flutter)과 아이폰 기능(위젯 저장소, 결제, 체험 기간)을 이어주는 다리예요.
final class HaruNative {
    static let shared = HaruNative()

    static let groupId = "group.com.isla0x.cleanTodo"
    static let productId = "haruring_pro"
    private static let keychainService = "com.isla0x.cleanTodo.trial"

    private var channel: FlutterMethodChannel?
    private var pendingLink: String?
    private var updatesTask: Task<Void, Never>?

    private var shared: UserDefaults {
        UserDefaults(suiteName: Self.groupId) ?? UserDefaults.standard
    }

    // MARK: 연결

    func attach(messenger: FlutterBinaryMessenger) {
        let ch = FlutterMethodChannel(name: "haruring/native", binaryMessenger: messenger)
        ch.setMethodCallHandler { [weak self] call, result in
            self?.handle(call, result)
        }
        channel = ch
        startTransactionListener()
    }

    /// 위젯을 눌러 앱이 열릴 때 들어오는 주소 (haruring://pro)
    func handleLink(_ url: URL) {
        guard url.scheme == "haruring" else { return }
        pendingLink = url.absoluteString
        channel?.invokeMethod("linkAvailable", arguments: nil)
    }

    // MARK: 호출 처리

    private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        switch call.method {
        case "widgetSync":
            let args = call.arguments as? [String: Any]
            if let items = args?["items"] as? String {
                shared.set(items, forKey: "items_v1")
            }
            if let pro = args?["pro"] as? String {
                shared.set(pro, forKey: "pro_v1")
            }
            WidgetCenter.shared.reloadAllTimelines()
            result(nil)

        case "takeToggles":
            let s = shared.string(forKey: "toggles_v1") ?? "[]"
            shared.removeObject(forKey: "toggles_v1")
            result(s)

        case "takePendingLink":
            let link = pendingLink
            pendingLink = nil
            result(link)

        case "proStatus":
            Task { @MainActor in
                let purchased = await Self.hasEntitlement()
                var out: [String: Any] = ["purchased": purchased]
                if let start = Self.trialStartMs() { out["trialStart"] = start }
                if let price = await Self.productPrice() { out["price"] = price }
                result(out)
            }

        case "startTrial":
            result(Self.startTrial())

        case "purchase":
            Task { @MainActor in
                result(await Self.purchase())
            }

        case "restore":
            Task { @MainActor in
                do {
                    try await AppStore.sync()
                } catch {
                    // 로그인 창을 닫는 등 동기화가 취소돼도 현재 구입 상태는 확인해요.
                }
                result(await Self.hasEntitlement())
            }

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: 결제 (StoreKit 2)

    static func hasEntitlement() async -> Bool {
        for await entitlement in Transaction.currentEntitlements {
            if case .verified(let t) = entitlement,
               t.productID == productId,
               t.revocationDate == nil {
                return true
            }
        }
        return false
    }

    static func productPrice() async -> String? {
        do {
            let products = try await Product.products(for: [productId])
            return products.first?.displayPrice
        } catch {
            return nil
        }
    }

    static func purchase() async -> String {
        do {
            guard let product = try await Product.products(for: [productId]).first else {
                return "error:product"
            }
            let outcome = try await product.purchase()
            switch outcome {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    await transaction.finish()
                    return "purchased"
                case .unverified:
                    return "error:unverified"
                }
            case .userCancelled:
                return "cancelled"
            case .pending:
                return "pending"
            @unknown default:
                return "error:unknown"
            }
        } catch {
            return "error:\(error.localizedDescription)"
        }
    }

    /// 가족 공유·결제 승인 대기 같이 앱 밖에서 끝난 결제를 받아요.
    private func startTransactionListener() {
        updatesTask?.cancel()
        updatesTask = Task.detached { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let transaction) = update {
                    await transaction.finish()
                }
                await MainActor.run {
                    self?.channel?.invokeMethod("proChanged", arguments: nil)
                }
            }
        }
    }

    // MARK: 체험 시작일 (키체인: 앱을 지웠다 깔아도 남아요)

    static func trialStartMs() -> Int64? {
        guard let s = keychainRead("trialStart"), let v = Int64(s) else { return nil }
        return v
    }

    static func startTrial() -> Int64 {
        if let existing = trialStartMs() { return existing }
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        keychainWrite("trialStart", String(now))
        return now
    }

    private static func keychainQuery(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
        ]
    }

    private static func keychainRead(_ account: String) -> String? {
        var query = keychainQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func keychainWrite(_ account: String, _ value: String) {
        let base = keychainQuery(account)
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }
}
