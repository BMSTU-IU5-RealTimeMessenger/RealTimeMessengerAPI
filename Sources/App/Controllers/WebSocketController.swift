//
//  WebSocketController.swift
//
//  Created by Dmitriy Permyakov on 19.02.2024.
//

import Vapor

// Создаем контроллер для обработки WebSocket соединений
final class WebSocketController: RouteCollection {

    func boot(routes: RoutesBuilder) throws {
        // Обработчик для веб-сокета
        routes.webSocket("socket", onUpgrade: handleSocketUpgrade)
    }

    // Метод для обработки обновления соединения до WebSocket
    func handleSocketUpgrade(req: Request, ws: WebSocket) {
        print("ПОДКЛЮЧЕНИЕ")

        // Отправляем клиенту сообщение о успешном подключении
        ws.send("Вы успешно подключились")

        // Обработчик для получения сообщений от клиента
        ws.onText { ws, text in
            guard let data = text.data(using: .utf8) else { return }
            do {
                let msg = try JSONDecoder().decode(Message.self, from: data)

                switch msg.event {
                case "connection":
                    print("here")
                    self.connectionHandler(ws: ws, msg: msg)
                case "message":
                    print(msg)
                default:
                    break
                }
            } catch {
                print("Ошибка при декодировании сообщения: \(error)")
            }
        }

        // Обработчик закрытия соединения
        ws.onClose.whenComplete { _ in
            print("Отключение")
        }
    }

    // Обработчик подключения
    func connectionHandler(ws: WebSocket, msg: Message) {
        print(msg)

        // Отправляем сообщение всем клиентам
        let response = "Пользователь с \(msg.userName) подключён"
        ws.send(response)
    }
}

// Структура для представления JSON сообщения
struct Message: Content {
    let event: String
    let id: Int
    let userName: String
}
