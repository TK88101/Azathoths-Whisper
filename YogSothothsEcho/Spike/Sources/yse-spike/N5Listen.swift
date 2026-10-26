import Foundation
import Network
import ProbeShared

// N5 的 Mac 端：明文 TCP 單次監聽，配合 iPad 探針（ProbeApp）驗證區域網路、Bonjour 與 Keychain 在側載下可用。
// N5 不驗 TLS（TLS 選型屬 N4 與 S2），也不證明身分（只證明 Bonjour＋TCP 可達；身分由使用者目視比對 challenge）。
// 訊息格式與解析只有一份：ProbeShared 的 N5Message（iPad 端同一份）。
// 不寫檔：只 print 連線次數、被拒次數、對端 IP 與錯誤類型；challenge 不承載機密。只在家用 Wi-Fi 執行。
enum N5Listen {
    static let serviceName = "YSE N5 Probe"
    static let liveTimeout: TimeInterval = 180
    static let selfTestTimeout: TimeInterval = 10
    private static let closeDelay: TimeInterval = 0.5
    private static let queue = DispatchQueue(label: "yse-spike.n5")

    /// 現場用：只綁 Wi-Fi 並以 Bonjour 廣播，只接受第一個連線，之後立即停止監聽
    static func run() async -> Bool {
        let challenge = N5Message.makeChallenge()
        print("n5-listen: challenge \(challenge)（iPad 畫面的數字須與此一致）")
        print("n5-listen: 在 Wi-Fi 上廣播 \(N5Message.serviceType) \"\(serviceName)\"，最長等待 \(Int(liveTimeout)) 秒")
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .wifi
        let served = await serve(challenge: challenge, parameters: parameters, advertise: true, timeout: liveTimeout)
        served.report(prefix: "n5-listen")
        if !served.delivered, served.accepted == 0, served.error != "timeout" {
            print("n5-listen: listener 沒能在 Wi-Fi 介面上啟動（有線、熱點或 Wi-Fi 關閉時會如此）；只在家用 Wi-Fi 執行")
        }
        return served.delivered
    }

    /// 自測：走與現場相同的 serve，只是限定迴路介面、不廣播，再以迴路 client 收一行並用 N5Message 解析
    static func selfTest() async -> Bool {
        let challenge = N5Message.makeChallenge()
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        let (ports, portSink) = AsyncStream<NWEndpoint.Port>.makeStream()
        async let served = serve(challenge: challenge, parameters: parameters, advertise: false,
                                 timeout: selfTestTimeout, ready: portSink)
        var received: String?
        for await port in ports {
            received = await receiveLine(port: port)
            break
        }
        let result = await served
        let ok = result.delivered && received == challenge
        print("n5 self-test: \(ok ? "收發成功" : "失敗（\(received == nil ? "沒收到有效訊息" : "內容不符")）")")
        if !ok { result.report(prefix: "n5 self-test") }
        return ok
    }

    // MARK: 伺服端

    private struct Served: Sendable {
        let accepted: Int
        let rejected: Int
        let peer: String?
        let delivered: Bool
        let error: String?

        func report(prefix: String) {
            print("\(prefix): 接受 \(accepted) 個連線（對端 \(peer ?? "—")）、拒絕 \(rejected) 個，"
                  + (delivered ? "已送出訊息" : "未送出訊息"))
            if let error { print("\(prefix): 錯誤類型 \(error)") }
        }
    }

    /// 連線計數：第一個接受，之後的一律拒絕並計數（看得出是否被搶）
    private final class Tally: @unchecked Sendable {
        private let lock = NSLock()
        private var seen = 0
        private var peerText: String?

        func admit(_ endpoint: NWEndpoint) -> Bool {
            lock.withLock {
                seen += 1
                if seen == 1 { peerText = Self.host(of: endpoint) }
                return seen == 1
            }
        }

        func served(delivered: Bool, error: String?) -> Served {
            lock.withLock {
                Served(accepted: min(seen, 1), rejected: max(seen - 1, 0), peer: peerText, delivered: delivered,
                       error: error)
            }
        }

        /// 只取 IP，不取埠與名稱
        private static func host(of endpoint: NWEndpoint) -> String? {
            if case .hostPort(let host, _) = endpoint { return "\(host)" }
            return nil
        }
    }

    private static func serve(challenge: String, parameters: NWParameters, advertise: Bool,
                              timeout: TimeInterval,
                              ready: AsyncStream<NWEndpoint.Port>.Continuation? = nil) async -> Served {
        defer { ready?.finish() }   // 沒 ready 就結束時讓自測的 for await 返回
        let tally = Tally()
        let listener: NWListener
        do {
            listener = try NWListener(using: parameters)
        } catch {
            return tally.served(delivered: false, error: errorKind(error))
        }
        if advertise { listener.service = NWListener.Service(name: serviceName, type: N5Message.serviceType) }
        let result: Served = await withCheckedContinuation { continuation in
            let once = OneShot(continuation)
            listener.newConnectionHandler = { connection in
                guard tally.admit(connection.endpoint) else {
                    connection.cancel()
                    return
                }
                listener.cancel()   // 只接受一次：第一個連線到手就停止監聽
                connection.start(queue: queue)
                deliver(challenge, over: connection) { error in
                    once.resume(tally.served(delivered: error == nil, error: error.map(errorKind)))
                }
            }
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready: if let port = listener.port { ready?.yield(port) }
                case .failed(let error): once.resume(tally.served(delivered: false, error: errorKind(error)))
                default: break
                }
            }
            listener.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) {
                once.resume(tally.served(delivered: false, error: "timeout"))
            }
        }
        listener.cancel()
        return result
    }

    /// 送出一行訊息並以 FIN 收尾；稍後才 cancel，避免剛送完就 RST 掉尚在途中的資料
    private static func deliver(_ challenge: String, over connection: NWConnection,
                                completion: @escaping @Sendable (NWError?) -> Void) {
        let payload = Data((N5Message.make(challenge: challenge) ?? "").utf8)
        connection.send(content: payload, contentContext: .finalMessage, isComplete: true,
                        completion: .contentProcessed { error in
            completion(error)
            queue.asyncAfter(deadline: .now() + closeDelay) { connection.cancel() }
        })
    }

    // MARK: 自測用戶端

    /// 迴路 client：累積到 N5Message.frame 判定出 challenge 或無效為止
    private static func receiveLine(port: NWEndpoint.Port) async -> String? {
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        let connection = NWConnection(host: "127.0.0.1", port: port, using: parameters)
        defer { connection.cancel() }
        guard await NetProbe.waitReady(connection, label: "n5 client", queue: queue, timeout: selfTestTimeout) == nil
        else { return nil }
        return await withCheckedContinuation { continuation in
            let once = OneShot(continuation)
            readFrame(connection, buffer: Data(), once: once)
            queue.asyncAfter(deadline: .now() + selfTestTimeout) { once.resume(nil) }
        }
    }

    private static func readFrame(_ connection: NWConnection, buffer: Data, once: OneShot<String?>) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: N5Message.maxFrameBytes) { data, _, isComplete, error in
            var next = buffer
            if let data { next.append(data) }
            switch N5Message.frame(next) {
            case .challenge(let challenge): once.resume(challenge)
            case .invalid: once.resume(nil)
            case .needMore:
                if error != nil || isComplete { once.resume(nil) } else { readFrame(connection, buffer: next, once: once) }
            }
        }
    }

    private static func errorKind(_ error: Error) -> String {
        (error as? NWError).map(networkErrorText) ?? String(describing: type(of: error))
    }
}
