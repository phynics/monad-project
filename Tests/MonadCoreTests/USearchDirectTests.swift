import Testing
import Foundation
import USearch

@Suite struct USearchDirectTests {
    
    // @Test("Direct USearch Index Add")
    // func testDirectAdd() throws {
    //     let index = try USearchIndex.make(
    //         metric: .cos,
    //         dimensions: 4,
    //         connectivity: 16,
    //         quantization: .f32
    //     )
    //     
    //     // Manual vector creation
    //     let vector: [Float] = [1.0, 0.0, 0.0, 0.0]
    //     let key: UInt64 = 1
    //     
    //     try vector.withUnsafeBufferPointer { buffer in
    //         guard let baseAddress = buffer.baseAddress else { return }
    //         try index.addSingle(key: USearchKey(key), vector: baseAddress)
    //     }
    //     
    //     #expect(try index.count == 1)
    // }
}
