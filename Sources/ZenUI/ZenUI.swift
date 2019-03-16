//
//  Extensions.swift
//  ZenUI
//
//  Created by admin on 21/12/2018.
//

import ZenNIO
import Stencil

extension HttpResponse {
    
    public func send(template: String, context: [String : Any] = [:]) throws {
        let fsLoader = FileSystemLoader(paths: ["templates/"])
        let environment = Environment(loader: fsLoader)
        let html = try environment.renderTemplate(name: template, context: context)
        addHeader(.contentType, value: "text/html; charset=utf-8")
        send(data: html.data(using: .utf8)!)
    }
}
