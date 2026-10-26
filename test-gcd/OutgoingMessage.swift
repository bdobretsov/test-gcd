import Foundation

struct OutgoingMessage: Equatable {
    enum Status: Equatable { case pending, sending, sent, failed }
    let id: UUID
    let chatID: String
    let text: String
    var status: Status
}

enum TransportError: Error {
    case offline
    case timeout        // запрос ушёл, ответа нет
    case server(code: Int)
}

protocol Cancellable { func cancel() }

protocol MessageTransport {
    /// completion вызывается на произвольной фоновой очереди.
    @discardableResult
    func send(chatID: String, text: String,
              completion: @escaping (Result<String, TransportError>) -> Void) -> Cancellable
}

protocol NetworkMonitor: AnyObject {
    var isOnline: Bool { get }
    var onChange: ((Bool) -> Void)? { get set }   // вызывается на фоновой очереди
}

/// Мок сервера: случайные задержки, ~30% ошибок.
/// При .timeout сервер на самом деле СОХРАНИЛ сообщение.
final class FlakyTransport: MessageTransport {
    private let lock = NSLock()
    private var _received: [(chatID: String, text: String)] = []
    var received: [(chatID: String, text: String)] { lock.withLock { _received } }

    private final class Token: Cancellable {
        let item: DispatchWorkItem
        init(_ item: DispatchWorkItem) { self.item = item }
        func cancel() { item.cancel() }
    }

    func send(chatID: String, text: String,
              completion: @escaping (Result<String, TransportError>) -> Void) -> Cancellable {
        let item = DispatchWorkItem { [self] in
            switch Int.random(in: 0..<10) {
            case 0: completion(.failure(.server(code: 503)))
            case 1: completion(.failure(.offline))
            case 2:
                lock.withLock { _received.append((chatID, text)) }
                completion(.failure(.timeout))
            default:
                lock.withLock { _received.append((chatID, text)) }
                completion(.success(UUID().uuidString))
            }
        }
        DispatchQueue.global().asyncAfter(
            deadline: .now() + .milliseconds(Int.random(in: 50...800)), execute: item)
        return Token(item)
    }
}
