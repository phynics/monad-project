import Shared
import Testing

@testable import MonadAssistant

@Suite struct TokenEstimatorTests {

    @Test("Test empty string estimation")
    func emptyString() {
        #expect(TokenEstimator.estimate(text: "") == 0)
    }

    @Test("Test basic english estimation")
    func basicEnglish() {
        // "Hello" is 5 chars, ~5/4 tokens = 1.25 -> 2 tokens (rounded up)
        let count = TokenEstimator.estimate(text: "Hello")
        #expect(count > 0)
    }

    @Test("Test multi-byte character estimation")
    func multiByteCharacters() {
        // Emoji and special chars should still be estimated reasonably
        let count = TokenEstimator.estimate(text: "🚀 Monad Assistant")
        #expect(count > 0)
    }

    @Test("Test large input estimation")
    func largeInput() {
        let largeString = String(repeating: "word ", count: 1000)
        let count = TokenEstimator.estimate(text: largeString)
        #expect(count > 1000)
    }
}
