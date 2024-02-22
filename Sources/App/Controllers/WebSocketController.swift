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
                    let stringMessage = "Пользователь с ником: [ \(msg.userName) ] добавлен в сессию"
                    Logger.log(kind: .connection, message: stringMessage)
                    ws.send(stringMessage)

                case .message:
                    var msg = try JSONDecoder().decode(Message.self, from: data)
                    msg.state = [.error, .received, .received].randomElement()!
                    let jsonData = try JSONEncoder().encode(msg)
                    guard let jsonString = String(data: jsonData, encoding: .utf8) else {
                        Logger.log(kind: .error, message: "Ошибка преобразование jsonData: [ \(msg) ] к jsonString")
                        return
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        // Если обнаружена ошибка, сообщаем только пользователю
                        switch msg.state {
                        case .error:
                            ws.send(jsonString)
                        default:
                            self.wsClients.values.forEach {
                                Logger.log(kind: .message, message: msg)
                                $0.send(jsonString)
                            }
                        }
                    }
                }

            } catch {
                Logger.log(kind: .error, message: error)
            }
        }

        ws.onClose.whenComplete { [weak self] _ in
            guard let self, let key = wsClients.first(where: { $0.value === ws })?.key else { return }
            wsClients.removeValue(forKey: key)
            Logger.log(kind: .close, message: "Пользователь с ником: [ \(key) ] удалён из очереди")
        }
    }
}

// MARK: - Models

enum MessageKind: String, Codable {
    case connection
    case message
}

struct MessageAbstract: Codable {
    let kind: MessageKind
}

struct Message: Codable {
    var id: UUID
    let kind: MessageKind
    let userName: String
    let dispatchDate: Date
    let message: String
    var state: State
}

enum State: String, Codable {
    case progress
    case received
    case error
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
        case message
        case close
        case connection
    }
}
