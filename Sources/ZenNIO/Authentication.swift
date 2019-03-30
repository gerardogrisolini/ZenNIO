//
//  Authentication.swift
//  ZenNIO
//
//  Created by admin on 22/12/2018.
//

import Foundation

public typealias Login = ((_ username: String, _ password: String) -> (Bool))

public struct Account : Codable {
    public var username: String = ""
    public var password: String = ""
}

public struct Token : Codable {
    public var basic: String = ""
    public var bearer: String = ""
    
    public init(basic: String) {
        self.basic = basic
    }

    public init(bearer: String) {
        self.bearer = bearer
    }
}

class Authentication {
    
    private let provider: AuthenticationProtocol
    private let handler: Login
    
    init(handler: @escaping Login) {
        provider = ZenIoC.shared.resolve() as AuthenticationProtocol
        self.handler = handler
    }
    
    func makeRoutesAndHandlers(router: Router) {
        
        router.get("/auth") { request, response in
            //response.addHeader(.link, value: "</assets/logo.png>; rel=preload; as=image, </assets/style.css>; rel=preload; as=style, </assets/scripts.js>; rel=preload; as=script")
            //response.addHeader(.cache, value: "no-cache")
            //response.addHeader(.cache, value: "max-age=1440") // 1 days
            //response.addHeader(.expires, value: Date(timeIntervalSinceNow: TimeInterval(1440.0 * 60.0)).rfc5322Date)
            
            let html = self.provider.html(ip: request.clientIp)
            response.send(html: html)
            response.completed()
        }

        router.post("/api/logout") { request, response in
            ZenNIO.sessions.remove(id: request.session!.id)
            //response.addHeader(.setCookie, value: "token=; expires=Thu, 01 Jan 1970 00:00:00 UTC; path=/;")
            //response.addHeader(.setCookie, value: "sessionId=; expires=Thu, 01 Jan 1970 00:00:00 UTC; path=/;")
            response.completed(.noContent)
        }
        
        router.post("/api/login") { request, response in
            do {
                guard let data = request.bodyData else {
                    throw HttpError.badRequest
                }
                
                let account = try JSONDecoder().decode(Account.self, from: data)
                if self.handler(account.username, account.password) {
                    let data = Date().timeIntervalSinceNow.description.data(using: .utf8)!
                    let token = Token(bearer: data.base64EncodedString())
                    let session = ZenNIO.sessions.new(id: request.session!.id, token: token)
                    ZenNIO.sessions.set(session: session)
                    //response.addHeader(.setCookie, value: "token=\(token.bearer)")
                    try response.send(json: token)
                    response.completed()
                } else {
                    response.completed(.unauthorized)
                }
            } catch HttpError.badRequest {
                response.completed(.badRequest)
            } catch {
                print(error)
                response.completed(.internalServerError)
            }
        }
        
        router.get("/assets/favicon.ico") { request, response in
            response.addHeader(.contentType, value: "image/x-icon")
            response.send(data: self.provider.icon)
            response.completed()
        }

        router.get("/assets/scripts.js") { request, response in
            response.addHeader(.contentType, value: "text/javascript")
            response.send(data: self.provider.script())
            response.completed()
        }

        router.get("/assets/style.css") { request, response in
            response.addHeader(.contentType, value: "text/css")
            response.send(data: self.provider.style)
            response.completed()
        }

        router.get("/assets/logo.png") { request, response in
            response.addHeader(.contentType, value: "image/png")
            response.send(data: self.provider.logo)
            response.completed()
        }
    }
}

protocol AuthenticationProtocol {
    var icon: Data { get }
    var logo: Data { get }
    var style: Data { get }
    func html(ip: String) -> String
    func script() -> Data
}

struct AuthenticationProvider : AuthenticationProtocol {
//    <link rel="preload" href="/assets/logo.png" as="image">
//    <link rel="preload" href="/assets/style.css" as="style">
//    <link rel="preload" href="/assets/scripts.js" as="script">
//    <script src="/assets/scripts.js?id=2"></script>
//    <script src="/assets/scripts.js?id=3"></script>
//    <script src="/assets/scripts.js?id=4" defer=""></script>
//    <script src="/assets/scripts.js?id=5" defer=""></script>
//    <script src="/assets/scripts.js?id=6" defer=""></script>
//    <script src="/assets/scripts.js?id=7" async=""></script>
//    <script src="/assets/scripts.js?id=8" async=""></script>
//    <script src="/assets/scripts.js?id=9" async=""></script>
//    <script src="/assets/scripts.js?id=10" async=""></script>

    func html(ip: String) -> String {
        let content: String = """
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>ZenNIO - authentication</title>
    <base href="/">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="robots" content="noindex">
    <link rel="icon" type="image/x-icon" href="/assets/favicon.ico">
    <link rel="stylesheet" href="/assets/style.css">
    <script src="/assets/scripts.js"></script>
</head>
<body onload="init()">
    <div class="wrapper fadeInDown">
        <div id="formContent">
            <img class="fadeIn first" id="logo" alt="Logo" src="/assets/logo.png">
            <h2 class="active underlineHover"> Authentication </h2>
            <br/>
            <p> Hello from ZenNIO </p>
            <p> IP: \(ip) </p>
            <div id="auth"></div>
            <div id="formFooter">
                <a class="underlineHover" href="#">Information privacy</a>
            </div>
        </div>
    </div>
</body>
</html>

"""
        return content
    }
 
    func script() -> Data {
        let content = """
var token = localStorage.getItem('token');
function signIn() {
    const username = document.getElementById("username").value;
    const password = document.getElementById("password").value;
    if (username === '' || password == '') { return; }
    const json = JSON.stringify({
        username: username,
        password: password
    });
    fetch('/api/login', {
        headers: {
            'Content-Type': 'application/json;charset=UTF-8',
        },
        method : 'POST',
        cache: 'no-cache',
        body: json
    })
    .then(response => response.status == 401 ? alert('401 - Unauthorized') : response.json())
    .then(json => saveToken(json))
    .catch(error => console.log(error));
}
function saveToken(json) {
    if (json && json.bearer) {
        localStorage.setItem('token', 'Bearer ' + json.bearer);
        document.cookie = 'token=' + json.bearer + '; expires=Thu, 01 Jan 2050 00:00:00 UTC; path=/;';
        if (document.referrer) {
            self.location = document.referrer;
        } else {
            location.reload();
        }
    }
}
function signOut() {
    fetch('/api/logout', {
        headers: {
            'Content-Type': 'application/json;charset=UTF-8',
            'Authorization': token
        },
        method : 'POST',
        cache: 'no-cache'
    })
    .then(response => response.text())
    .then(json => removeToken())
    .catch(error => console.log(error));
}
function removeToken() {
    document.cookie = 'token=' + localStorage.getItem('token') + '; expires=Thu, 01 Jan 1970 00:00:00 UTC; path=/;';
    localStorage.removeItem('token');
    if (document.referrer) {
        self.location = document.referrer;
    } else {
        location.reload();
    }
}
function init() {
    var html = '';
    if (token === null) {
html = `
    <form>
        <input class="fadeIn second" type="text" id="username" placeholder="username"/>
        <input class="fadeIn third" type="password" id="password" placeholder="password"/>
        <input class="fadeIn fourth" type="button" value="Sign In" onclick="signIn()"/>
    </form>
`;
    } else {
html = `
    <p class="fadeIn second"> ${token} </p>
    <p class="fadeIn third"> <input type="button" value="Sign Out" onclick="signOut()"/> </p>
`;
    }
    document.getElementById("auth").innerHTML = html;
}

"""
        return content.data(using: .utf8)!
    }

    var style: Data {
        let content = """
@import url('https://fonts.googleapis.com/css?family=Poppins');

/* BASIC */

html {
    background-color: #56baed;
}

body {
    font-family: "Poppins", sans-serif;
    height: 100vh;
}

a {
    color: #92badd;
    display:inline-block;
    text-decoration: none;
    font-weight: 400;
}

h2 {
    text-align: center;
    font-size: x-large;
    font-weight: 600;
    display:inline-block;
    margin: 40px 8px 10px 8px;
    color: #cccccc;
}

/* STRUCTURE */

.wrapper {
    display: flex;
    align-items: center;
    flex-direction: column;
    justify-content: center;
    width: 100%;
    min-height: 100%;
    padding: 20px;
}

#formContent {
    -webkit-border-radius: 10px 10px 10px 10px;
    border-radius: 10px 10px 10px 10px;
    background: #fff;
    padding: 30px;
    width: 90%;
    max-width: 450px;
    position: relative;
    padding: 0px;
    -webkit-box-shadow: 0 30px 60px 0 rgba(0,0,0,0.3);
    box-shadow: 0 30px 60px 0 rgba(0,0,0,0.3);
    text-align: center;
}

#formFooter {
    background-color: #f6f6f6;
    border-top: 1px solid #dce8f1;
    padding: 25px;
    text-align: center;
    -webkit-border-radius: 0 0 10px 10px;
    border-radius: 0 0 10px 10px;
}

/* TABS */

h2.inactive {
    color: #cccccc;
}

h2.active {
    color: #0d0d0d;
    border-bottom: 2px solid #5fbae9;
}

/* FORM TYPOGRAPHY*/

input[type=button], input[type=submit], input[type=reset]  {
    background-color: #56baed;
    border: none;
    color: white;
    padding: 15px 80px;
    text-align: center;
    text-decoration: none;
    display: inline-block;
    text-transform: uppercase;
    font-size: 13px;
    width: 85%;
    -webkit-box-shadow: 0 10px 30px 0 rgba(95,186,233,0.4);
    box-shadow: 0 10px 30px 0 rgba(95,186,233,0.4);
    -webkit-border-radius: 5px 5px 5px 5px;
    border-radius: 5px 5px 5px 5px;
    margin: 5px 20px 40px 20px;
    -webkit-transition: all 0.3s ease-in-out;
    -moz-transition: all 0.3s ease-in-out;
    -ms-transition: all 0.3s ease-in-out;
    -o-transition: all 0.3s ease-in-out;
    transition: all 0.3s ease-in-out;
}

input[type=button]:hover, input[type=submit]:hover, input[type=reset]:hover  {
    background-color: #39ace7;
}

input[type=button]:active, input[type=submit]:active, input[type=reset]:active  {
    -moz-transform: scale(0.95);
    -webkit-transform: scale(0.95);
    -o-transform: scale(0.95);
    -ms-transform: scale(0.95);
    transform: scale(0.95);
}

input[type=text], input[type=password] {
    background-color: #f6f6f6;
    border: none;
    color: #0d0d0d;
    padding: 15px 32px;
    text-align: center;
    text-decoration: none;
    display: inline-block;
    font-size: 16px;
    margin: 5px;
    width: 85%;
    border: 2px solid #f6f6f6;
    -webkit-transition: all 0.5s ease-in-out;
    -moz-transition: all 0.5s ease-in-out;
    -ms-transition: all 0.5s ease-in-out;
    -o-transition: all 0.5s ease-in-out;
    transition: all 0.5s ease-in-out;
    -webkit-border-radius: 5px 5px 5px 5px;
    border-radius: 5px 5px 5px 5px;
}

input[type=text]:focus, input[type=password]:focus {
    background-color: #fff;
    border-bottom: 2px solid #5fbae9;
}

input[type=text]:placeholder, input[type=password]:placeholder {
    color: #cccccc;
}

/* ANIMATIONS */

/* Simple CSS3 Fade-in-down Animation */
.fadeInDown {
    -webkit-animation-name: fadeInDown;
    animation-name: fadeInDown;
    -webkit-animation-duration: 1s;
    animation-duration: 1s;
    -webkit-animation-fill-mode: both;
    animation-fill-mode: both;
}

@-webkit-keyframes fadeInDown {
    0% {
        opacity: 0;
        -webkit-transform: translate3d(0, -100%, 0);
        transform: translate3d(0, -100%, 0);
    }
    100% {
        opacity: 1;
        -webkit-transform: none;
        transform: none;
    }
}

@keyframes fadeInDown {
    0% {
        opacity: 0;
        -webkit-transform: translate3d(0, -100%, 0);
        transform: translate3d(0, -100%, 0);
    }
    100% {
        opacity: 1;
        -webkit-transform: none;
        transform: none;
    }
}

/* Simple CSS3 Fade-in Animation */
@-webkit-keyframes fadeIn { from { opacity:0; } to { opacity:1; } }
@-moz-keyframes fadeIn { from { opacity:0; } to { opacity:1; } }
@keyframes fadeIn { from { opacity:0; } to { opacity:1; } }

.fadeIn {
    opacity:0;
    -webkit-animation:fadeIn ease-in 1;
    -moz-animation:fadeIn ease-in 1;
    animation:fadeIn ease-in 1;
    
    -webkit-animation-fill-mode:forwards;
    -moz-animation-fill-mode:forwards;
    animation-fill-mode:forwards;
    
    -webkit-animation-duration:1s;
    -moz-animation-duration:1s;
    animation-duration:1s;
}

.fadeIn.first {
    -webkit-animation-delay: 0.4s;
    -moz-animation-delay: 0.4s;
    animation-delay: 0.4s;
}

.fadeIn.second {
    -webkit-animation-delay: 0.6s;
    -moz-animation-delay: 0.6s;
    animation-delay: 0.6s;
}

.fadeIn.third {
    -webkit-animation-delay: 0.8s;
    -moz-animation-delay: 0.8s;
    animation-delay: 0.8s;
}

.fadeIn.fourth {
    -webkit-animation-delay: 1s;
    -moz-animation-delay: 1s;
    animation-delay: 1s;
}

/* Simple CSS3 Fade-in Animation */
.underlineHover:after {
    display: block;
    left: 0;
    bottom: -10px;
    width: 0;
    height: 2px;
    background-color: #56baed;
    content: "";
    transition: width 0.2s;
}

.underlineHover:hover {
    color: #0d0d0d;
}

.underlineHover:hover:after{
    width: 100%;
}

/* OTHERS */

*:focus {
    outline: none;
}

#icon {
    width:60%;
}

#logo {
    position: absolute;
    height: 100px;
    top: 15px;
    right: 15px;
}

* {
    box-sizing: border-box;
}

"""
        return content.data(using: .utf8)!
    }
    
    var icon: Data {
        let content = "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"
        
        return Data(base64Encoded: content, options: .init(rawValue: 0))!
    }
    
    var logo: Data {
        let content = "iVBORw0KGgoAAAANSUhEUgAAAIQAAACDCAIAAADDIyRIAAAACXBIWXMAAAsTAAALEwEAmpwYAAA/iGlUWHRYTUw6Y29tLmFkb2JlLnhtcAAAAAAAPD94cGFja2V0IGJlZ2luPSLvu78iIGlkPSJXNU0wTXBDZWhpSHpyZVN6TlRjemtjOWQiPz4KPHg6eG1wbWV0YSB4bWxuczp4PSJhZG9iZTpuczptZXRhLyIgeDp4bXB0az0iQWRvYmUgWE1QIENvcmUgNS42LWMxMzggNzkuMTU5ODI0LCAyMDE2LzA5LzE0LTAxOjA5OjAxICAgICAgICAiPgogICA8cmRmOlJERiB4bWxuczpyZGY9Imh0dHA6Ly93d3cudzMub3JnLzE5OTkvMDIvMjItcmRmLXN5bnRheC1ucyMiPgogICAgICA8cmRmOkRlc2NyaXB0aW9uIHJkZjphYm91dD0iIgogICAgICAgICAgICB4bWxuczp4bXBNTT0iaHR0cDovL25zLmFkb2JlLmNvbS94YXAvMS4wL21tLyIKICAgICAgICAgICAgeG1sbnM6c3RFdnQ9Imh0dHA6Ly9ucy5hZG9iZS5jb20veGFwLzEuMC9zVHlwZS9SZXNvdXJjZUV2ZW50IyIKICAgICAgICAgICAgeG1sbnM6c3RSZWY9Imh0dHA6Ly9ucy5hZG9iZS5jb20veGFwLzEuMC9zVHlwZS9SZXNvdXJjZVJlZiMiCiAgICAgICAgICAgIHhtbG5zOmRjPSJodHRwOi8vcHVybC5vcmcvZGMvZWxlbWVudHMvMS4xLyIKICAgICAgICAgICAgeG1sbnM6cGhvdG9zaG9wPSJodHRwOi8vbnMuYWRvYmUuY29tL3Bob3Rvc2hvcC8xLjAvIgogICAgICAgICAgICB4bWxuczp4bXA9Imh0dHA6Ly9ucy5hZG9iZS5jb20veGFwLzEuMC8iCiAgICAgICAgICAgIHhtbG5zOnRpZmY9Imh0dHA6Ly9ucy5hZG9iZS5jb20vdGlmZi8xLjAvIgogICAgICAgICAgICB4bWxuczpleGlmPSJodHRwOi8vbnMuYWRvYmUuY29tL2V4aWYvMS4wLyI+CiAgICAgICAgIDx4bXBNTTpEb2N1bWVudElEPmFkb2JlOmRvY2lkOnBob3Rvc2hvcDo1NzA1Y2M5YS1hMDI5LTExN2ItOTY5Yi1mZGJlM2M1NTk4NTM8L3htcE1NOkRvY3VtZW50SUQ+CiAgICAgICAgIDx4bXBNTTpJbnN0YW5jZUlEPnhtcC5paWQ6NGZhZGQ2MzEtNmY1Ny00OThiLWJiMTAtZmZjYTMwNDdhMzlmPC94bXBNTTpJbnN0YW5jZUlEPgogICAgICAgICA8eG1wTU06T3JpZ2luYWxEb2N1bWVudElEPjlEMzFBRUYyOTRBNjVGNzFDRjQ3OUJCMTVDMTk5RkI3PC94bXBNTTpPcmlnaW5hbERvY3VtZW50SUQ+CiAgICAgICAgIDx4bXBNTTpIaXN0b3J5PgogICAgICAgICAgICA8cmRmOlNlcT4KICAgICAgICAgICAgICAgPHJkZjpsaSByZGY6cGFyc2VUeXBlPSJSZXNvdXJjZSI+CiAgICAgICAgICAgICAgICAgIDxzdEV2dDphY3Rpb24+c2F2ZWQ8L3N0RXZ0OmFjdGlvbj4KICAgICAgICAgICAgICAgICAgPHN0RXZ0Omluc3RhbmNlSUQ+eG1wLmlpZDpmYzBkOTJkMC0zOTUzLTRlNTAtOGFhYS1mNjlhNDg4MTgxMzI8L3N0RXZ0Omluc3RhbmNlSUQ+CiAgICAgICAgICAgICAgICAgIDxzdEV2dDp3aGVuPjIwMTgtMDUtMjRUMjM6Mzk6NTIrMDI6MDA8L3N0RXZ0OndoZW4+CiAgICAgICAgICAgICAgICAgIDxzdEV2dDpzb2Z0d2FyZUFnZW50PkFkb2JlIFBob3Rvc2hvcCBDQyAyMDE3IChNYWNpbnRvc2gpPC9zdEV2dDpzb2Z0d2FyZUFnZW50PgogICAgICAgICAgICAgICAgICA8c3RFdnQ6Y2hhbmdlZD4vPC9zdEV2dDpjaGFuZ2VkPgogICAgICAgICAgICAgICA8L3JkZjpsaT4KICAgICAgICAgICAgICAgPHJkZjpsaSByZGY6cGFyc2VUeXBlPSJSZXNvdXJjZSI+CiAgICAgICAgICAgICAgICAgIDxzdEV2dDphY3Rpb24+Y29udmVydGVkPC9zdEV2dDphY3Rpb24+CiAgICAgICAgICAgICAgICAgIDxzdEV2dDpwYXJhbWV0ZXJzPmZyb20gaW1hZ2UvanBlZyB0byBpbWFnZS9wbmc8L3N0RXZ0OnBhcmFtZXRlcnM+CiAgICAgICAgICAgICAgIDwvcmRmOmxpPgogICAgICAgICAgICAgICA8cmRmOmxpIHJkZjpwYXJzZVR5cGU9IlJlc291cmNlIj4KICAgICAgICAgICAgICAgICAgPHN0RXZ0OmFjdGlvbj5kZXJpdmVkPC9zdEV2dDphY3Rpb24+CiAgICAgICAgICAgICAgICAgIDxzdEV2dDpwYXJhbWV0ZXJzPmNvbnZlcnRlZCBmcm9tIGltYWdlL2pwZWcgdG8gaW1hZ2UvcG5nPC9zdEV2dDpwYXJhbWV0ZXJzPgogICAgICAgICAgICAgICA8L3JkZjpsaT4KICAgICAgICAgICAgICAgPHJkZjpsaSByZGY6cGFyc2VUeXBlPSJSZXNvdXJjZSI+CiAgICAgICAgICAgICAgICAgIDxzdEV2dDphY3Rpb24+c2F2ZWQ8L3N0RXZ0OmFjdGlvbj4KICAgICAgICAgICAgICAgICAgPHN0RXZ0Omluc3RhbmNlSUQ+eG1wLmlpZDo0ZmFkZDYzMS02ZjU3LTQ5OGItYmIxMC1mZmNhMzA0N2EzOWY8L3N0RXZ0Omluc3RhbmNlSUQ+CiAgICAgICAgICAgICAgICAgIDxzdEV2dDp3aGVuPjIwMTgtMDUtMjRUMjM6Mzk6NTIrMDI6MDA8L3N0RXZ0OndoZW4+CiAgICAgICAgICAgICAgICAgIDxzdEV2dDpzb2Z0d2FyZUFnZW50PkFkb2JlIFBob3Rvc2hvcCBDQyAyMDE3IChNYWNpbnRvc2gpPC9zdEV2dDpzb2Z0d2FyZUFnZW50PgogICAgICAgICAgICAgICAgICA8c3RFdnQ6Y2hhbmdlZD4vPC9zdEV2dDpjaGFuZ2VkPgogICAgICAgICAgICAgICA8L3JkZjpsaT4KICAgICAgICAgICAgPC9yZGY6U2VxPgogICAgICAgICA8L3htcE1NOkhpc3Rvcnk+CiAgICAgICAgIDx4bXBNTTpEZXJpdmVkRnJvbSByZGY6cGFyc2VUeXBlPSJSZXNvdXJjZSI+CiAgICAgICAgICAgIDxzdFJlZjppbnN0YW5jZUlEPnhtcC5paWQ6ZmMwZDkyZDAtMzk1My00ZTUwLThhYWEtZjY5YTQ4ODE4MTMyPC9zdFJlZjppbnN0YW5jZUlEPgogICAgICAgICAgICA8c3RSZWY6ZG9jdW1lbnRJRD45RDMxQUVGMjk0QTY1RjcxQ0Y0NzlCQjE1QzE5OUZCNzwvc3RSZWY6ZG9jdW1lbnRJRD4KICAgICAgICAgICAgPHN0UmVmOm9yaWdpbmFsRG9jdW1lbnRJRD45RDMxQUVGMjk0QTY1RjcxQ0Y0NzlCQjE1QzE5OUZCNzwvc3RSZWY6b3JpZ2luYWxEb2N1bWVudElEPgogICAgICAgICA8L3htcE1NOkRlcml2ZWRGcm9tPgogICAgICAgICA8ZGM6Zm9ybWF0PmltYWdlL3BuZzwvZGM6Zm9ybWF0PgogICAgICAgICA8cGhvdG9zaG9wOkNvbG9yTW9kZT4zPC9waG90b3Nob3A6Q29sb3JNb2RlPgogICAgICAgICA8cGhvdG9zaG9wOklDQ1Byb2ZpbGUvPgogICAgICAgICA8eG1wOkNyZWF0ZURhdGU+MjAxOC0wMS0yOVQxNTozNTozMiswMTowMDwveG1wOkNyZWF0ZURhdGU+CiAgICAgICAgIDx4bXA6TW9kaWZ5RGF0ZT4yMDE4LTA1LTI0VDIzOjM5OjUyKzAyOjAwPC94bXA6TW9kaWZ5RGF0ZT4KICAgICAgICAgPHhtcDpNZXRhZGF0YURhdGU+MjAxOC0wNS0yNFQyMzozOTo1MiswMjowMDwveG1wOk1ldGFkYXRhRGF0ZT4KICAgICAgICAgPHhtcDpDcmVhdG9yVG9vbD5BZG9iZSBQaG90b3Nob3AgQ0MgMjAxNyAoTWFjaW50b3NoKTwveG1wOkNyZWF0b3JUb29sPgogICAgICAgICA8dGlmZjpJbWFnZVdpZHRoPjEzMjwvdGlmZjpJbWFnZVdpZHRoPgogICAgICAgICA8dGlmZjpJbWFnZUxlbmd0aD4xMzE8L3RpZmY6SW1hZ2VMZW5ndGg+CiAgICAgICAgIDx0aWZmOkJpdHNQZXJTYW1wbGU+CiAgICAgICAgICAgIDxyZGY6U2VxPgogICAgICAgICAgICAgICA8cmRmOmxpPjg8L3JkZjpsaT4KICAgICAgICAgICAgICAgPHJkZjpsaT44PC9yZGY6bGk+CiAgICAgICAgICAgICAgIDxyZGY6bGk+ODwvcmRmOmxpPgogICAgICAgICAgICA8L3JkZjpTZXE+CiAgICAgICAgIDwvdGlmZjpCaXRzUGVyU2FtcGxlPgogICAgICAgICA8dGlmZjpQaG90b21ldHJpY0ludGVycHJldGF0aW9uPjI8L3RpZmY6UGhvdG9tZXRyaWNJbnRlcnByZXRhdGlvbj4KICAgICAgICAgPHRpZmY6T3JpZW50YXRpb24+MTwvdGlmZjpPcmllbnRhdGlvbj4KICAgICAgICAgPHRpZmY6U2FtcGxlc1BlclBpeGVsPjM8L3RpZmY6U2FtcGxlc1BlclBpeGVsPgogICAgICAgICA8dGlmZjpYUmVzb2x1dGlvbj43MjAwMDAvMTAwMDA8L3RpZmY6WFJlc29sdXRpb24+CiAgICAgICAgIDx0aWZmOllSZXNvbHV0aW9uPjcyMDAwMC8xMDAwMDwvdGlmZjpZUmVzb2x1dGlvbj4KICAgICAgICAgPHRpZmY6UmVzb2x1dGlvblVuaXQ+MjwvdGlmZjpSZXNvbHV0aW9uVW5pdD4KICAgICAgICAgPGV4aWY6RXhpZlZlcnNpb24+MDIyMTwvZXhpZjpFeGlmVmVyc2lvbj4KICAgICAgICAgPGV4aWY6Q29sb3JTcGFjZT42NTUzNTwvZXhpZjpDb2xvclNwYWNlPgogICAgICAgICA8ZXhpZjpQaXhlbFhEaW1lbnNpb24+MTMyPC9leGlmOlBpeGVsWERpbWVuc2lvbj4KICAgICAgICAgPGV4aWY6UGl4ZWxZRGltZW5zaW9uPjEzMTwvZXhpZjpQaXhlbFlEaW1lbnNpb24+CiAgICAgIDwvcmRmOkRlc2NyaXB0aW9uPgogICA8L3JkZjpSREY+CjwveDp4bXBtZXRhPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgCiAgICAgICAgICAgICAgICAgICAgICAg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"
        
        return Data(base64Encoded: content, options: .init(rawValue: 0))!
    }
}

