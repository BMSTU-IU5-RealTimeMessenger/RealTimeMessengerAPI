//
//  WebSocketController.swift
//
//  Created by Dmitriy Permyakov on 19.02.2024.
//

import Vapor

// Создаем контроллер для обработки WebSocket соединений
final class WebSocketController: RouteCollection {

    private var wsClients: [String: WebSocket] = [:]

    func boot(routes: RoutesBuilder) throws {
        routes.webSocket("socket", onUpgrade: handleSocketUpgrade)
    }

    func handleSocketUpgrade(req: Request, ws: WebSocket) {
        Logger.log(message: "Подключение")

        ws.send("Вы успешно подключились")

        ws.onText { [weak self] ws, text in
            guard let self, let data = text.data(using: .utf8) else {
                Logger.log(kind: .error, message: "Неверный привод типа `text.data(using: .utf8)`")
                return
            }

            do {
                let msgKind = try JSONDecoder().decode(MessageAbstract.self, from: data)

                switch msgKind.kind {
                case .connection:
                    let msg = try JSONDecoder().decode(Message.self, from: data)
                    wsClients[msg.userName] = ws
                    let stringMessage = "Пользователь с ником: \(msg.userName) добавлен в сессию"
                    Logger.log(message: stringMessage)
                    ws.send(stringMessage)

                case .message:
                    let msg = try JSONDecoder().decode(Message.self, from: data)
                    Logger.log(message: msg)
                    wsClients.values.forEach {
                        $0.send(text)
                    }
                }

            } catch {
                Logger.log(kind: .error, message: error)
            }
        }

        ws.onClose.whenComplete { [weak self] _ in
            guard let self, let key = wsClients.first(where: { $0.value === ws })?.key else { return }
            wsClients.removeValue(forKey: key)
            Logger.log(message: "Пользователь с ником: \(key) удалён из очереди")
        }
    }
}

// MARK: - Models

enum MessageKind: String, Decodable {
    case connection
    case message
}

struct MessageAbstract: Decodable {
    let kind: MessageKind
}

struct Message: Decodable {
    let userName: String
    let dispatchDate: Date
    let message: String
}

// MARK: - Logger

final class Logger {
    private init() {}

    static func log(kind: Kind = .info, message: Any, function: String = #function) {
        print("[ \(kind.rawValue.uppercased()) ]: [ \(Date()) ]: [ \(function) ]")
        print(message)
        print()
    }

    enum Kind: String, Hashable {
        case info
        case error
        case warning
    }
}
