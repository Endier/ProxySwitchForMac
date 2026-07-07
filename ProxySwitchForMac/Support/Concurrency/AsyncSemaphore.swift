//  AsyncSemaphore.swift
//  ProxySwitchForMac
//
//  并发限流原语。

/// 异步信号量，用于限制并发执行的 networksetup 进程数，
/// 避免活跃服务较多时瞬时大量 fork 造成资源争用。
actor AsyncSemaphore {
    private var slots: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        self.slots = max(1, limit)
    }

    func acquire() async {
        if slots > 0 {
            slots -= 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() async {
        if let waiter = waiters.first {
            waiters.removeFirst()
            waiter.resume()
        } else {
            slots += 1
        }
    }
}
