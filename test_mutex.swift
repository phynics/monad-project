import Synchronization

func test() {
    let mutex = Mutex(false)
    let closure: @escaping () -> Void = {
        mutex.withLock { $0 = true }
    }
}
