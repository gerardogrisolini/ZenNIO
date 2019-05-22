//
//  HTTP2ResponseCompressor.swift
//  ZenNIOH2
//
//  Created by Gerardo Grisolini on 15/05/2019.
//

import CNIOExtrasZlib
import NIO
import NIOHTTP1
import NIOHTTP2
import NIOHPACK

extension StringProtocol {
    /// Test if this `Collection` starts with the unicode scalars of `needle`.
    ///
    /// - note: This will be faster than `String.startsWith` as no unicode normalisations are performed.
    ///
    /// - parameters:
    ///    - needle: The `Collection` of `Unicode.Scalar`s to match at the beginning of `self`
    /// - returns: If `self` started with the elements contained in `needle`.
    func startsWithSameUnicodeScalars<S: StringProtocol>(string needle: S) -> Bool {
        return self.unicodeScalars.starts(with: needle.unicodeScalars)
    }
}


/// Given a header value, extracts the q value if there is one present. If one is not present,
/// returns the default q value, 1.0.
private func qValueFromHeader<S: StringProtocol>(_ text: S) -> Float {
    let headerParts = text.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)
    guard headerParts.count > 1 && headerParts[1].count > 0 else {
        return 1
    }
    
    // We have a Q value.
    let qValue = Float(headerParts[1].split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)[1]) ?? 0
    if qValue < 0 || qValue > 1 || qValue.isNaN {
        return 0
    }
    return qValue
}

/// A HTTPResponseCompressor is a duplex channel handler that handles automatic streaming compression of
/// HTTP responses. It respects the client's Accept-Encoding preferences, including q-values if present,
/// and ensures that clients are served the compression algorithm that works best for them.
///
/// This compressor supports gzip and deflate. It works best if many writes are made between flushes.
///
/// Note that this compressor performs the compression on the event loop thread. This means that compressing
/// some resources, particularly those that do not benefit from compression or that could have been compressed
/// ahead-of-time instead of dynamically, could be a waste of CPU time and latency for relatively minimal
/// benefit. This channel handler should be present in the pipeline only for dynamically-generated and
/// highly-compressible content, which will see the biggest benefits from streaming compression.
public final class HTTP2ResponseCompressor: ChannelDuplexHandler, RemovableChannelHandler {
    public typealias InboundIn = HTTP2Frame
    public typealias InboundOut = HTTP2Frame
    public typealias OutboundIn = HTTP2Frame
    public typealias OutboundOut = HTTP2Frame

    public enum CompressionError: Error {
        case uncompressedWritesPending
        case noDataToWrite
    }
    
    fileprivate enum CompressionAlgorithm: String {
        case gzip = "gzip"
        case deflate = "deflate"
    }
    
    // Private variable for storing stream data.
    private var stream = z_stream()
    
    private var algorithm: CompressionAlgorithm?
    
    // A queue of accept headers.
    private var acceptQueue = [String]()
    
    private var pendingResponse: PartialHTTP2Frame!
    private var pendingWritePromise: EventLoopPromise<Void>!
    
    private let initialByteBufferCapacity: Int
    
    public init(initialByteBufferCapacity: Int = 1024) {
        self.initialByteBufferCapacity = initialByteBufferCapacity
    }
    
    public func handlerAdded(context: ChannelHandlerContext) {
        pendingResponse = PartialHTTP2Frame(bodyBuffer: context.channel.allocator.buffer(capacity: initialByteBufferCapacity))
        pendingWritePromise = context.eventLoop.makePromise()
    }
    
    public func handlerRemoved(context: ChannelHandlerContext) {
        pendingWritePromise?.fail(CompressionError.uncompressedWritesPending)
        if algorithm != nil {
            deinitializeEncoder()
            algorithm = nil
        }
    }
    
    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let frame = self.unwrapInboundIn(data)
        
        if case .headers(let head) = frame.payload {
            let encoding = head.headers[canonicalForm: "accept-encoding"]
            print(encoding)
            acceptQueue.append(contentsOf: encoding)
        }
        
        context.fireChannelRead(data)
    }
    
    public func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        var frame = unwrapOutboundIn(data)
        print(frame.streamID)
        switch frame.payload {
        case .headers(var responseHead):
            algorithm = compressionAlgorithm()
            guard algorithm != nil else {
                context.write(wrapOutboundOut(frame), promise: promise)
                return
            }
            // Previous handlers in the pipeline might have already set this header even though
            // they should not as it is compressor responsibility to decide what encoding to use
            responseHead.headers.add(name: "content-encoding", value: algorithm!.rawValue)
            initializeEncoder(encoding: algorithm!)
            frame.payload = .headers(responseHead)
            pendingResponse.bufferResponseHead(frame)
            pendingWritePromise.futureResult.cascade(to: promise)
            print(responseHead.headers)
        case .data(_):
            if algorithm != nil {
                pendingResponse.bufferBodyPart(&frame)
                pendingWritePromise.futureResult.cascade(to: promise)
                emitPendingWrites(context: context)
                algorithm = nil
                deinitializeEncoder()
            } else {
                context.write(data, promise: promise)
            }
        default:
            break
        }
    }
    
    public func flush(context: ChannelHandlerContext) {
        //emitPendingWrites(context: context)
        context.flush()
    }
    
    /// Determines the compression algorithm to use for the next response.
    ///
    /// Returns the compression algorithm to use, or nil if the next response
    /// should not be compressed.
    private func compressionAlgorithm() -> CompressionAlgorithm? {
        //let acceptHeaders = acceptQueue.removeFirst()
        
        var gzipQValue: Float = -1
        var deflateQValue: Float = -1
        var anyQValue: Float = -1
        
        for acceptHeader in acceptQueue {
            if acceptHeader.hasPrefix("gzip") || acceptHeader.hasPrefix("x-gzip") {
                gzipQValue = qValueFromHeader(acceptHeader)
            } else if acceptHeader.hasPrefix("deflate") {
                deflateQValue = qValueFromHeader(acceptHeader)
            } else if acceptHeader.hasPrefix("*") {
                anyQValue = qValueFromHeader(acceptHeader)
            }
        }
        
        if gzipQValue > 0 || deflateQValue > 0 {
            return gzipQValue > deflateQValue ? .gzip : .deflate
        } else if anyQValue > 0 {
            // Though gzip is usually less well compressed than deflate, it has slightly
            // wider support because it's unabiguous. We therefore default to that unless
            // the client has expressed a preference.
            return .gzip
        }
        
        return nil
    }
    
    /// Set up the encoder for compressing data according to a specific
    /// algorithm.
    private func initializeEncoder(encoding: CompressionAlgorithm) {
        // zlib docs say: The application must initialize zalloc, zfree and opaque before calling the init function.
        stream.zalloc = nil
        stream.zfree = nil
        stream.opaque = nil
        
        let windowBits: Int32
        switch encoding {
        case .deflate:
            windowBits = 15
        case .gzip:
            windowBits = 16 + 15
        }
        
        let rc = CNIOExtrasZlib_deflateInit2(&stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED, windowBits, 8, Z_DEFAULT_STRATEGY)
        precondition(rc == Z_OK, "Unexpected return from zlib init: \(rc)")
    }
    
    private func deinitializeEncoder() {
        // We deliberately discard the result here because we just want to free up
        // the pending data.
        deflateEnd(&stream)
    }
    
    /// Emits all pending buffered writes to the network, optionally compressing the
    /// data. Resets the pending write buffer and promise.
    ///
    /// Called either when a HTTP end message is received or our flush() method is called.
    private func emitPendingWrites(context: ChannelHandlerContext) {
        let writesToEmit = pendingResponse.flush(compressor: &stream, allocator: context.channel.allocator)
        var pendingPromise = pendingWritePromise
        
        if let writeHead = writesToEmit.0 {
            context.write(wrapOutboundOut(writeHead), promise: pendingPromise)
            pendingPromise = nil
        }
        
        if let writeBody = writesToEmit.1 {
            context.write(wrapOutboundOut(writeBody), promise: pendingPromise)
            pendingPromise = nil
        }
        
        // If we still have the pending promise, we never emitted a write. Fail the promise,
        // as anything that is listening for its data somehow lost it.
        if let stillPendingPromise = pendingPromise {
            stillPendingPromise.fail(CompressionError.noDataToWrite)
        }
        
        // Reset the pending promise.
        pendingWritePromise = context.eventLoop.makePromise()
    }
}
/// A buffer object that allows us to keep track of how much of a HTTP response we've seen before
/// a flush.
///
/// The strategy used in this module is that we want to have as much information as possible before
/// we compress, and to compress as few times as possible. This is because in the ideal situation we
/// will have a complete HTTP response to compress in one shot, allowing us to update the content
/// length, rather than force the response to be chunked. It is much easier to do the right thing
/// if we can encapsulate our ideas about how HTTP responses in an entity like this.
private struct PartialHTTP2Frame {
    var head: HTTP2Frame?
    var body: ByteBuffer
    private let initialBufferSize: Int
    
    var isCompleteResponse: Bool {
        return head != nil
    }
    
    init(bodyBuffer: ByteBuffer) {
        body = bodyBuffer
        initialBufferSize = bodyBuffer.capacity
        head = nil
    }
    
    mutating func bufferResponseHead(_ head: HTTP2Frame) {
        precondition(self.head == nil)
        self.head = head
    }
    
    mutating func bufferBodyPart(_ bodyPart: inout HTTP2Frame) {
        _ = withUnsafeBytes(of: &bodyPart) { bytes in
            body.writeBytes(bytes)
        }
    }
    
    private mutating func clear() {
        head = nil
        body.clear()
        body.reserveCapacity(initialBufferSize)
    }
    
    mutating private func compressBody(compressor: inout z_stream, allocator: ByteBufferAllocator, flag: Int32) -> ByteBuffer? {
        guard body.readableBytes > 0 else {
            return nil
        }
        
        // deflateBound() provides an upper limit on the number of bytes the input can
        // compress to. We add 5 bytes to handle the fact that Z_SYNC_FLUSH will append
        // an empty stored block that is 5 bytes long.
        let bufferSize = Int(deflateBound(&compressor, UInt(body.readableBytes)))
        var outputBuffer = allocator.buffer(capacity: bufferSize)
        
        // Now do the one-shot compression. All the data should have been consumed.
        compressor.oneShotDeflate(from: &body, to: &outputBuffer, flag: flag)
        precondition(body.readableBytes == 0)
        precondition(outputBuffer.readableBytes > 0)
        return outputBuffer
    }
    
    /// Flushes the buffered data into its constituent parts.
    ///
    /// Returns a three-tuple of a HTTP response head, compressed body bytes, and any end that
    /// may have been buffered. Each of these types is optional.
    ///
    /// If the head is flushed, it will have had its headers mutated based on whether we had the whole
    /// response or not. If nil, the head has previously been emitted.
    ///
    /// If the body is nil, it means no writes were buffered (that is, our buffer of bytes has no
    /// readable bytes in it). This should usually mean that no write is issued.
    ///
    /// Calling this function resets the buffer, freeing any excess memory allocated in the internal
    /// buffer and losing all copies of the other HTTP data. At this point it may freely be reused.
    mutating func flush(compressor: inout z_stream, allocator: ByteBufferAllocator) -> (HTTP2Frame?, HTTP2Frame?) {
        let flag = Z_FINISH
        
        let body = compressBody(compressor: &compressor, allocator: allocator, flag: flag)
        if let bodyLength = body?.readableBytes, isCompleteResponse && bodyLength > 0 {
            
            switch head!.payload {
            case .headers(var h):
                var headers = HPACKHeaders()
                h.headers.forEach { (name, value, indexable) in
                    if name != "content-length" {
                        headers.add(name: name, value: value)
                    }
                }
                headers.add(name: "content-length", value: "\(bodyLength)")
                h.headers = headers
                head!.payload = .headers(h)
                print(headers)
                break
            default:
                break
            }

            var payload = HTTP2Frame.FramePayload.Data(data: .byteBuffer(body!))
            payload.endStream = true
            let frameData = HTTP2Frame(streamID: head!.streamID, payload: .data(payload))
            clear()
            return (head, frameData)
        }
        
        clear()
        return (nil, nil)
    }
}

private extension z_stream {
    /// Executes deflate from one buffer to another buffer. The advantage of this method is that it
    /// will ensure that the stream is "safe" after each call (that is, that the stream does not have
    /// pointers to byte buffers any longer).
    mutating func oneShotDeflate(from: inout ByteBuffer, to: inout ByteBuffer, flag: Int32) {
        defer {
            self.avail_in = 0
            self.next_in = nil
            self.avail_out = 0
            self.next_out = nil
        }
        
        from.readWithUnsafeMutableReadableBytes { dataPtr in
            let typedPtr = dataPtr.baseAddress!.assumingMemoryBound(to: UInt8.self)
            let typedDataPtr = UnsafeMutableBufferPointer(start: typedPtr,
                                                          count: dataPtr.count)
            
            self.avail_in = UInt32(typedDataPtr.count)
            self.next_in = typedDataPtr.baseAddress!
            
            let rc = deflateToBuffer(buffer: &to, flag: flag)
            precondition(rc == Z_OK || rc == Z_STREAM_END, "One-shot compression failed: \(rc)")
            
            return typedDataPtr.count - Int(self.avail_in)
        }
    }
    
    /// A private function that sets the deflate target buffer and then calls deflate.
    /// This relies on having the input set by the previous caller: it will use whatever input was
    /// configured.
    private mutating func deflateToBuffer(buffer: inout ByteBuffer, flag: Int32) -> Int32 {
        var rc = Z_OK
        
        buffer.writeWithUnsafeMutableBytes { outputPtr in
            let typedOutputPtr = UnsafeMutableBufferPointer(start: outputPtr.baseAddress!.assumingMemoryBound(to: UInt8.self),
                                                            count: outputPtr.count)
            self.avail_out = UInt32(typedOutputPtr.count)
            self.next_out = typedOutputPtr.baseAddress!
            rc = deflate(&self, flag)
            return typedOutputPtr.count - Int(self.avail_out)
        }
        
        return rc
    }
}
