import Vapor

//struct Message: Content {
//    let name: String
//    let age: Int
//}

func routes(_ app: Application) throws {
    app.get { req async in
        "It works!"
    }

    app.get("hello") { req async -> String in
        "Hello, world!"
    }

//    app.get("messages") { req -> [Message] in
//        [
//            .init(name: "Dima1", age: 11),
//            .init(name: "Dima2", age: 12),
//            .init(name: "Dima3", age: 13),
//            .init(name: "Dima4", age: 14),
//        ]
//    }
}
