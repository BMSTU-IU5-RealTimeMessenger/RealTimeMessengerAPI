//
//  HttpMessage.swift
//  RealTimeMessengerAPI
//
//  Created by Dmitriy Permyakov on 29.04.2024.
//

import Foundation
import Vapor

struct HttpMessage: Content, Codable {
    let data: String?
    let error: String?
}

struct HttpMessageData: Content, Codable {
    let uid: String
    let message: String
    let messageKind: MessageKind
    let userName: String
}
