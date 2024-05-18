//
//  WebSocketController.swift
//  RealTimeMessengerAPI
//
//  Created by Dmitriy Permyakov on 19.02.2024.
//

import Vapor

// MARK: - WebSocketController

final class WebSocketController: RouteCollection {

    // MARK: Private Values

    private var wsClients: Set<Client> = Set()

    // MARK: Router

    func boot(routes: RoutesBuilder) throws {

        // Groups
        let apiGroup = routes.grouped("api", "v1")
        let messageGroup = apiGroup.grouped("message")

        // HTTP
        messageGroup.post(use: handleMessageFromExternalService)
        messageGroup.post("proxy", use: proxyExternalService)

        // WebSocket
        routes.webSocket("socket", onUpgrade: handleSocketUpgrade)
    }
}

// MARK: - Web Sockets

private extension WebSocketController {

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
                    try messageHandlerWithService(ws: ws, data: data)

                case .close:
                    break

                case .error:
                    break
                }

            } catch {
                Logger.log(kind: .error, message: error)
            }
        }

        ws.onClose.whenComplete { [weak self] _ in
            guard let self, let key = wsClients.first(where: { $0.ws === ws })?.userName else {
                return
            }
            do {
                try closeHandler(ws: ws, key: key)
            } catch {
                Logger.log(kind: .error, message: error)
            }
        }
    }

    func connectionHandler(ws: WebSocket, data: Data) throws {
        let msg = try JSONDecoder().decode(Message.self, from: data)
        if (wsClients.first(where: { $0.userName == msg.userName }) != nil) {
            Logger.log(kind: .error, message: "Имя пользователя занято")
            throw Abort(.custom(code: HTTPResponseStatus.badRequest.code, reasonPhrase: "Имя пользователя занято"))
        }
        let newClient = Client(ws: ws, userName: msg.userName)
        wsClients.insert(newClient)
        Logger.log(kind: .connection, message: "Пользователь с ником: [ \(msg.userName) ] добавлен в сессию")
        sendMessageToExternalService(message: msg) { result in
            switch result {
            case .success:
                Logger.log(kind: .info, message: "Сообщение успешно доставленно на сервис транспортного уровня")
            case let .failure(error):
                Logger.log(kind: .error, message: error.localizedDescription)
            }
        }
    }

    func messageHandlerWithService(ws: WebSocket, data: Data) throws {
        let msg = try JSONDecoder().decode(Message.self, from: data)
        sendMessageToExternalService(message: msg) { result in
            switch result {
            case .success:
                Logger.log(kind: .info, message: "Сообщение успешно доставленно на сервис транспортного уровня")
            case let .failure(error):
                Logger.log(kind: .error, message: error.localizedDescription)
            }
        }
    }

    func closeHandler(ws: WebSocket, key: String) throws {
        guard let deletedClient = wsClients.remove(Client(ws: ws, userName: key)) else {
            Logger.log(kind: .error, message: "Не удалось удалить пользователя: [ \(key) ]")
            throw Abort(.internalServerError)
        }

        Logger.log(kind: .close, message: "Пользователь с ником: [ \(deletedClient.userName) ] удалён из очереди")
        let msgClose = Message(
            id: UUID().uuidString,
            kind: .close,
            userName: key,
            dispatchDate: Date(),
            message: .clear
        )
        sendMessageToExternalService(message: msgClose) { result in
            switch result {
            case .success:
                Logger.log(kind: .info, message: "Сообщение успешно доставленно на сервис транспортного уровня")
            case let .failure(error):
                Logger.log(kind: .error, message: error.localizedDescription)
            }
        }
    }
}

// MARK: - HTTP

private extension WebSocketController {

    /// Get message from application layer to transport layer
    func handleMessageFromExternalService(_ req: Request) async throws -> ServerResponse {
        let httpMessageWithString = try req.content.decode(HttpMessage.self)
        if let error = httpMessageWithString.error {
            let msg = Message(
                id: UUID().uuidString,
                kind: .error,
                userName: .clear,
                dispatchDate: Date(),
                message: .clear
            )
            let msgString = try msg.encodeMessage()
            // Отправляем всем клиентом текст об ошибке отправки сообщения
            wsClients.forEach { client in
                client.ws.send(msgString)
            }
            return ServerResponse(
                status: HTTPResponseStatus.ok.code,
                description: "сообщили челам про ошибку: \(error)"
            )
        }

        guard let objectString = httpMessageWithString.data?.data(using: .utf8) else {
            throw Abort(.custom(
                code: HTTPResponseStatus.badRequest.code,
                reasonPhrase: "объект `data` не может быть nil, если error уже не nil"
            ))
        }

        let messageData = try JSONDecoder().decode(HttpMessageData.self, from: objectString)

        let msg = Message(
            id: messageData.uid,
            kind: messageData.messageKind,
            userName: messageData.userName,
            dispatchDate: Date(),
            message: messageData.message
        )

        let msgString = try msg.encodeMessage()
        wsClients.forEach { client in
            if client.userName != msg.userName {
                client.ws.send(msgString)
            }
        }

        return ServerResponse(
            status: HTTPResponseStatus.ok.code,
            description: "Пользователь: \(messageData.userName) получил сообщение: \(messageData.message)"
        )
    }

    /// Send message from application layer to transport layer
    func sendMessageToExternalService(message: Message, completion: @escaping MKResultBlock<Bool, KingError>) {
        let messageData = HttpMessageData(
            uid: message.id,
            message: message.message,
            messageKind: message.kind,
            userName: message.userName
        )

        let msgData: Data
        do {
            msgData = try JSONEncoder().encode(messageData)
        } catch {
            completion(.failure(.error(error)))
            Logger.log(kind: .error, message: "Ошибка кодирования данных в json объект `MessageData`")
            return
        }

        // FIXME: Заменить на URL Влада
        let externalServiceURL = "http://127.0.0.1:2929/api/v1/message/proxy"
//        let externalServiceURL = "http://192.168.175.118:16000/send"
        APIManager.shared.post(urlString: externalServiceURL, msgData: msgData, completion: completion)
    }
    
    /// Ручка, имитирующая работу сервиса Влада на трансортном уровне.
    func proxyExternalService(_ req: Request) async throws -> String {
        let httpMessageData = try req.content.decode(HttpMessageData.self)
        Logger.log(message: "Имитация работы сервиса транспортного уровня. Полученно сообщение: \(httpMessageData)")
        let hasError = [false, true].randomElement()!
//        let hasError = [false].randomElement()!

        let httpMsg: HttpMessage
        // Формируем сообщение с ошибков
        if hasError {
            Logger.log(kind: .info, message: "Данные повреждены в фейковом сервисе")
            httpMsg = HttpMessage(data: nil, error: "Данные повреждены")
        } else {
            let msgContent = HttpMessageData(
                uid: httpMessageData.uid,
                message: httpMessageData.message,
                messageKind: httpMessageData.messageKind,
                userName: httpMessageData.userName
            )
            let msgData = try JSONEncoder().encode(msgContent)
            let msgString = String(data: msgData, encoding: .utf8)
            httpMsg = HttpMessage(
                data: msgString,
                error: nil
            )
        }
        let encodedMsgData: Data = try JSONEncoder().encode(httpMsg)
        APIManager.shared.post(
            urlString: "http://127.0.0.1:2929/api/v1/message",
            msgData: encodedMsgData
        ) { result in
            switch result {
            case .success:
                Logger.log(message: "Успешно отправлены данные назад")
            case let .failure(error):
                Logger.log(kind: .error, message: error.localizedDescription)
            }
        }
        return "Закончил отправку"
    }
}
