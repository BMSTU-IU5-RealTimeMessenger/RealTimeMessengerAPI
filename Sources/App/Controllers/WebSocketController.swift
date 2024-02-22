//
//  WebSocketController.swift
//
//  Created by Dmitriy Permyakov on 19.02.2024.
//

import Vapor

// MARK: - Client

struct Client: Hashable {
    var ws: WebSocket
    var userName: String
}

extension Client {

    static func == (lhs: Client, rhs: Client) -> Bool {
        lhs.userName == rhs.userName
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(userName)
    }
}

// MARK: - WebSocketController

final class WebSocketController: RouteCollection {

    private var wsClients: Set<Client> = Set()

    func boot(routes: RoutesBuilder) throws {
        routes.webSocket("socket", onUpgrade: handleSocketUpgrade)
    }

    func handleSocketUpgrade(req: Request, ws: WebSocket) {
        Logger.log(message: "Подключение")

        ws.onText { [weak self] ws, text in
            guard let self, let data = text.data(using: .utf8) else {
                Logger.log(kind: .error, message: "Неверный привод типа `text.data(using: .utf8)`")
                return
            }

            do {
                let msgKind = try JSONDecoder().decode(MessageAbstract.self, from: data)

                switch msgKind.kind {
                case .connection:
                    try connectionHandler(ws: ws, data: data)

                case .message:
                    try messageHandler(ws: ws, data: data)

                case .close:
                    break
                }

            } catch {
                Logger.log(kind: .error, message: error)
            }
        }

        ws.onClose.whenComplete { [weak self] _ in
            guard let self, let key = wsClients.first(where: { $0.ws === ws })?.userName else { return }
            do {
                try closeHandler(ws: ws, key: key)
            } catch {
                Logger.log(kind: .error, message: error)
            }
        }
    }

    func connectionHandler(ws: WebSocket, data: Data) throws {
        let msg = try JSONDecoder().decode(Message.self, from: data)
        let newClient = Client(ws: ws, userName: msg.userName)
        wsClients.insert(newClient)
        let msgConnection = Message(
            id: UUID(),
            kind: .connection,
            userName: msg.userName,
            dispatchDate: Date(),
            message: "",
            state: .received
        )
        let msgConnectionString = try msgConnection.encodeMessage()
        Logger.log(kind: .connection, message: "Пользователь с ником: [ \(msg.userName) ] добавлен в сессию")
        wsClients.forEach {
            $0.ws.send(msgConnectionString)
        }
    }

    func messageHandler(ws: WebSocket, data: Data) throws {
        var msg = try JSONDecoder().decode(Message.self, from: data)
        msg.state = [.error, .received, .received].randomElement()!
        let jsonString = try msg.encodeMessage()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            // Если обнаружена ошибка, сообщаем только пользователю
            switch msg.state {
            case .error:
                ws.send(jsonString)
            default:
                self.wsClients.forEach {
                    Logger.log(kind: .message, message: msg)
                    $0.ws.send(jsonString)
                }
            }
        }
    }

    func closeHandler(ws: WebSocket, key: String) throws {
        guard let deletedClient = wsClients.remove(Client(ws: ws, userName: key)) else {
            Logger.log(kind: .error, message: "Не удалось удалить пользователя: [ \(key) ]")
            return
        }
        Logger.log(kind: .close, message: "Пользователь с ником: [ \(deletedClient.userName) ] удалён из очереди")
        let msgConnection = Message(
            id: UUID(),
            kind: .close,
            userName: key,
            dispatchDate: Date(),
            message: "",
            state: .received
        )
        let msgConnectionString = try msgConnection.encodeMessage()
        wsClients.forEach {
            $0.ws.send(msgConnectionString)
        }
    }
}

// MARK: - Message Extenstion

extension Message {

    func encodeMessage() throws -> String {
        let msgData = try JSONEncoder().encode(self)
        guard let msgString = String(data: msgData, encoding: .utf8) else {
            throw KingError.dataToString
        }
        return msgString
    }
}

enum KingError: Error {
    case dataToString

    var localizedDescription: String {
        switch self {
        case .dataToString:
            return "Не получилось закодировать Data в строку"
        }
    }
}

// MARK: - Models

enum MessageKind: String, Codable {
    case connection
    case close
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

    enum Kind: String {
        case info
        case error
        case warning
        case message
        case close
        case connection
    }
}
