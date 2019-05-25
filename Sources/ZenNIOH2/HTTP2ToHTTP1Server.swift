//
//  HTTP2ToHTTP1Server.swift
//  ZenNIOH2
//
//  Created by Gerardo Grisolini on 24/05/2019.
//
/*
import NIO
import NIOHTTP1
import NIOHTTP2
import NIOHPACK

/// A simple channel handler that translates HTTP/2 concepts into HTTP/1 data types,
/// and vice versa, for use on the server side.
///
/// This channel handler should be used alongside the `HTTP2StreamMultiplexer` to
/// help provide a HTTP/1.1-like abstraction on top of a HTTP/2 multiplexed
/// connection.
public final class HTTP2ToHTTP1ServerCodec: ChannelInboundHandler, ChannelOutboundHandler {
    public typealias InboundIn = HTTP2Frame
    public typealias InboundOut = HTTPServerRequestPart
    
    public typealias OutboundIn = HTTPServerResponsePart
    public typealias OutboundOut = HTTP2Frame
    
    private let streamID: HTTP2StreamID
    
    private var headerStateMachine: HTTP2HeadersStateMachine = HTTP2HeadersStateMachine(mode: .server)
    
    public init(streamID: HTTP2StreamID) {
        self.streamID = streamID
    }
    
    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let frame = self.unwrapInboundIn(data)
        
        switch frame.payload {
        case .headers(let headerContent):
            do {
                if case .trailer = try self.headerStateMachine.newHeaders(block: headerContent.headers) {
                    context.fireChannelRead(self.wrapInboundOut(.end(HTTPHeaders(regularHeadersFrom: headerContent.headers))))
                } else {
                    let reqHead = try HTTPRequestHead(http2HeaderBlock: headerContent.headers)
                    context.fireChannelRead(self.wrapInboundOut(.head(reqHead)))
                    if headerContent.endStream {
                        context.fireChannelRead(self.wrapInboundOut(.end(nil)))
                    }
                }
            } catch {
                context.fireErrorCaught(error)
            }
        case .data(let dataContent):
            guard case .byteBuffer(let b) = dataContent.data else {
                preconditionFailure("Received non-byteBuffer IOData from network")
            }
            context.fireChannelRead(self.wrapInboundOut(.body(b)))
            if dataContent.endStream {
                context.fireChannelRead(self.wrapInboundOut(.end(nil)))
            }
        default:
            // Any other frame type is ignored.
            break
        }
    }
    
    var streamIds = ArraySlice<Int>()
 
    public func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let responsePart = self.unwrapOutboundIn(data)
        switch responsePart {
        case .head(let head):
            let h1 = HTTPHeaders(responseHead: head)
            var frame: HTTP2Frame
            if let pushStreamId = h1["push-stream-id"].first {
                let pushPromise = HTTP2Frame.FramePayload.PushPromise(
                    pushedStreamID: HTTP2StreamID(Int(pushStreamId)!),
                    headers: HPACKHeaders([
                        (":method", "GET"),
                        (":scheme", "https"),
                        (":path", h1["path"].first!),
                        (":authority", "localhost:8888")
                        ])
                )
                print("PUSH_PROMISE: (\(pushStreamId)) \(pushPromise.headers)")
                frame = HTTP2Frame(streamID: self.streamID, payload: .pushPromise(pushPromise))
            } else if let xSreamId = h1["x-stream-id"].first, let streamId = Int(xSreamId) {
                let payload = HTTP2Frame.FramePayload.Headers(headers: HPACKHeaders(httpHeaders: h1))
                if streamId != self.streamID.networkStreamID {
                    frame = HTTP2Frame(streamID: HTTP2StreamID(streamId), payload: .headers(payload))
                    streamIds.append(streamId)
                    print("HEADER_PROMISE: \(payload.headers)")
                } else {
                    frame = HTTP2Frame(streamID: self.streamID, payload: .headers(payload))
                    print("HEADER: \(payload.headers)")
                }
            } else {
                let payload = HTTP2Frame.FramePayload.Headers(headers: HPACKHeaders(httpHeaders: h1))
                print("HEADER: \(payload.headers)")
                frame = HTTP2Frame(streamID: self.streamID, payload: .headers(payload))
            }
            context.write(self.wrapOutboundOut(frame), promise: promise)

        case .body(let body):
 
            let streamId = streamIds.isEmpty ? self.streamID : HTTP2StreamID(streamIds.first!)
            print("\(streamIds.isEmpty ? "BODY" : "BODY_PROMISE"): \(streamId)")
            streamIds = streamIds.dropFirst()
            let payload = HTTP2Frame.FramePayload.Data(data: body)
            let frame = HTTP2Frame(streamID: streamId, payload: .data(payload))
            context.write(self.wrapOutboundOut(frame), promise: promise)
 
        case .end(let trailers):
 
            let payload: HTTP2Frame.FramePayload
            if let trailers = trailers {
                payload = .headers(.init(headers: HPACKHeaders(httpHeaders: trailers), endStream: true))
            } else {
                payload = .data(.init(data: .byteBuffer(context.channel.allocator.buffer(capacity: 0)), endStream: true))
            }
 
            let frame = HTTP2Frame(streamID: self.streamID, payload: payload)
            context.write(self.wrapOutboundOut(frame), promise: promise)
        }
    }
}


private extension HTTPMethod {
    /// Create a `HTTPMethod` from the string representation of that method.
    init(methodString: String) {
        switch methodString {
        case "GET":
            self = .GET
        case "PUT":
            self = .PUT
        case "ACL":
            self = .ACL
        case "HEAD":
            self = .HEAD
        case "POST":
            self = .POST
        case "COPY":
            self = .COPY
        case "LOCK":
            self = .LOCK
        case "MOVE":
            self = .MOVE
        case "BIND":
            self = .BIND
        case "LINK":
            self = .LINK
        case "PATCH":
            self = .PATCH
        case "TRACE":
            self = .TRACE
        case "MKCOL":
            self = .MKCOL
        case "MERGE":
            self = .MERGE
        case "PURGE":
            self = .PURGE
        case "NOTIFY":
            self = .NOTIFY
        case "SEARCH":
            self = .SEARCH
        case "UNLOCK":
            self = .UNLOCK
        case "REBIND":
            self = .REBIND
        case "UNBIND":
            self = .UNBIND
        case "REPORT":
            self = .REPORT
        case "DELETE":
            self = .DELETE
        case "UNLINK":
            self = .UNLINK
        case "CONNECT":
            self = .CONNECT
        case "MSEARCH":
            self = .MSEARCH
        case "OPTIONS":
            self = .OPTIONS
        case "PROPFIND":
            self = .PROPFIND
        case "CHECKOUT":
            self = .CHECKOUT
        case "PROPPATCH":
            self = .PROPPATCH
        case "SUBSCRIBE":
            self = .SUBSCRIBE
        case "MKCALENDAR":
            self = .MKCALENDAR
        case "MKACTIVITY":
            self = .MKACTIVITY
        case "UNSUBSCRIBE":
            self = .UNSUBSCRIBE
        default:
            self = .RAW(value: methodString)
        }
    }
}


internal extension String {
    /// Create a `HTTPMethod` from the string representation of that method.
    init(httpMethod: HTTPMethod) {
        switch httpMethod {
        case .GET:
            self = "GET"
        case .PUT:
            self = "PUT"
        case .ACL:
            self = "ACL"
        case .HEAD:
            self = "HEAD"
        case .POST:
            self = "POST"
        case .COPY:
            self = "COPY"
        case .LOCK:
            self = "LOCK"
        case .MOVE:
            self = "MOVE"
        case .BIND:
            self = "BIND"
        case .LINK:
            self = "LINK"
        case .PATCH:
            self = "PATCH"
        case .TRACE:
            self = "TRACE"
        case .MKCOL:
            self = "MKCOL"
        case .MERGE:
            self = "MERGE"
        case .PURGE:
            self = "PURGE"
        case .NOTIFY:
            self = "NOTIFY"
        case .SEARCH:
            self = "SEARCH"
        case .UNLOCK:
            self = "UNLOCK"
        case .REBIND:
            self = "REBIND"
        case .UNBIND:
            self = "UNBIND"
        case .REPORT:
            self = "REPORT"
        case .DELETE:
            self = "DELETE"
        case .UNLINK:
            self = "UNLINK"
        case .CONNECT:
            self = "CONNECT"
        case .MSEARCH:
            self = "MSEARCH"
        case .OPTIONS:
            self = "OPTIONS"
        case .PROPFIND:
            self = "PROPFIND"
        case .CHECKOUT:
            self = "CHECKOUT"
        case .PROPPATCH:
            self = "PROPPATCH"
        case .SUBSCRIBE:
            self = "SUBSCRIBE"
        case .MKCALENDAR:
            self = "MKCALENDAR"
        case .MKACTIVITY:
            self = "MKACTIVITY"
        case .UNSUBSCRIBE:
            self = "UNSUBSCRIBE"
        case .SOURCE:
            self = "SOURCE"
        case .RAW(let v):
            self = v
        }
    }
}


// MARK:- Methods for creating `HTTPRequestHead`/`HTTPResponseHead` objects from
// header blocks generated by the HTTP/2 layer.
internal extension HTTPRequestHead {
    /// Create a `HTTPRequestHead` from the header block produced by nghttp2.
    init(http2HeaderBlock headers: HPACKHeaders) throws {
        // A request head should have only up to four psuedo-headers.
        let method = HTTPMethod(methodString: try headers.peekPseudoHeader(name: ":method"))
        let version = HTTPVersion(major: 2, minor: 0)
        let uri = try headers.peekPseudoHeader(name: ":path")
        
        // Here we peek :scheme just to confirm it's there: we want the throw effect, but we don't care about the value.
        _ = try headers.peekPseudoHeader(name: ":scheme")
        
        let authority = try headers.peekPseudoHeader(name: ":authority")
        
        // We do a manual implementation of HTTPHeaders(regularHeadersFrom:) here because we may need to add an extra Host:
        // header here, and that can cause copies if we're unlucky. We need headers.count - 3 spaces: we remove :method,
        // :path, :scheme, and :authority, but we may add in Host.
        var rawHeaders: [(String, String)] = []
        rawHeaders.reserveCapacity(headers.count - 3)
        if !headers.contains(name: "host") {
            rawHeaders.append(("host", authority))
        }
        rawHeaders.appendRegularHeaders(from: headers)
        
        self.init(version: version, method: method, uri: uri, headers: HTTPHeaders(rawHeaders))
    }
}


internal extension HTTPResponseHead {
    /// Create a `HTTPResponseHead` from the header block produced by nghttp2.
    init(http2HeaderBlock headers: HPACKHeaders) throws {
        // A response head should have only one psuedo-header. We strip it off.
        let statusHeader = try headers.peekPseudoHeader(name: ":status")
        guard let integerStatus = Int(statusHeader, radix: 10) else {
            throw NIOHTTP2Errors.InvalidStatusValue(statusHeader)
        }
        let status = HTTPResponseStatus(statusCode: integerStatus)
        self.init(version: .init(major: 2, minor: 0), status: status, headers: HTTPHeaders(regularHeadersFrom: headers))
    }
}


extension HPACKHeaders {
    /// Grabs a pseudo-header from a header block. Does not remove it.
    ///
    /// - parameter:
    ///     - name: The header name to find.
    /// - returns: The value for this pseudo-header.
    /// - throws: If there is no such header, or multiple.
    internal func peekPseudoHeader(name: String) throws -> String {
        let value = self[name]
        switch value.count {
        case 0:
            throw NIOHTTP2Errors.MissingPseudoHeader(name)
        case 1:
            return value.first!
        default:
            throw NIOHTTP2Errors.DuplicatePseudoHeader(name)
        }
    }
}


extension HTTPHeaders {
    fileprivate init(requestHead: HTTPRequestHead, protocolString: String) throws {
        // To avoid too much allocation we create an array first, and then initialize the HTTPHeaders from it.
        // We want to ensure this array is large enough so we only have to allocate once. We will need an
        // array that is the same as the number of headers in requestHead.headers + 3: we're adding :path,
        // :method, and :scheme, and transforming Host to :authority.
        var newHeaders: [(String, String)] = []
        newHeaders.reserveCapacity(requestHead.headers.count + 3)
        
        // TODO(cory): This is potentially wrong if the URI contains more than just a path.
        newHeaders.append((":path", requestHead.uri))
        newHeaders.append((":method", String(httpMethod: requestHead.method)))
        newHeaders.append((":scheme", protocolString))
        
        // We store a place for the :authority header, even though we don't know what it is. We'll find it later and
        // change it when we do. This avoids us needing to potentially search this header block twice.
        var authorityHeader: String? = nil
        newHeaders.append((":authority", ""))
        
        // Now fill in the others, except for any Host header we might find, which will become an :authority header.
        for header in requestHead.headers {
            if header.name.lowercased() == "host" {
                if authorityHeader != nil {
                    throw NIOHTTP2Errors.DuplicateHostHeader()
                }
                
                authorityHeader = header.value
            } else {
                newHeaders.append((header.name, header.value))
            }
        }
        
        // Now we go back and fill in the authority header.
        guard let actualAuthorityHeader = authorityHeader else {
            throw NIOHTTP2Errors.MissingHostHeader()
        }
        newHeaders[3].1 = actualAuthorityHeader
        
        self.init(newHeaders)
    }
    
    fileprivate init(responseHead: HTTPResponseHead) {
        // To avoid too much allocation we create an array first, and then initialize the HTTPHeaders from it.
        // This array will need to be the size of the response headers + 1, for the :status field.
        var newHeaders: [(String, String)] = []
        newHeaders.reserveCapacity(responseHead.headers.count + 1)
        newHeaders.append((":status", String(responseHead.status.code)))
        responseHead.headers.forEach { newHeaders.append(($0.name, $0.value)) }
        
        self.init(newHeaders)
    }
    
    internal init(regularHeadersFrom oldHeaders: HPACKHeaders) {
        // We need to create an array to write the header fields into.
        var newHeaders: [(String, String)] = []
        newHeaders.reserveCapacity(oldHeaders.count)
        newHeaders.appendRegularHeaders(from: oldHeaders)
        self.init(newHeaders)
    }
}


extension Array where Element == (String, String) {
    mutating func appendRegularHeaders(from headers: HPACKHeaders) {
        for (name, value, _) in headers {
            if name.first == ":" {
                continue
            }
            
            self.append((name, value))
        }
    }
}
*/
