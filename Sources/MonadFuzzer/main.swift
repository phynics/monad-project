import Foundation
import MonadCore

@_cdecl("LLVMFuzzerTestOneInput")
public func LLVMFuzzerTestOneInput(_ data: UnsafePointer<UInt8>, _ size: Int) -> Int32 {
    let buffer = UnsafeBufferPointer(start: data, count: size)
    let input = Data(buffer)
    
    guard let inputString = String(data: input, encoding: .utf8) else {
        return 0
    }
    
    // Fuzz StreamingParser
    let parser = StreamingParser()
    _ = parser.process(inputString)
    _ = parser.finalize()
    
    return 0
}
