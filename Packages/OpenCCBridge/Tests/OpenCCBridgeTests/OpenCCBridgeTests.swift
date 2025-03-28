// Copyright (c) 2022 and onwards The McBopomofo Authors.
//
// Permission is hereby granted, free of charge, to any person
// obtaining a copy of this software and associated documentation
// files (the "Software"), to deal in the Software without
// restriction, including without limitation the rights to use,
// copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the
// Software is furnished to do so, subject to the following
// conditions:
//
// The above copyright notice and this permission notice shall be
// included in all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
// EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
// OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
// NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
// HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
// WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
// FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
// OTHER DEALINGS IN THE SOFTWARE.

import Testing

@testable import OpenCCBridge

@Suite("Test OpenCCBridge")
final class OpenCCBridgeTests {

    @Test("Test Traditional Chinese to Simplified Chinese")
    func testTC2SC()  {
        let text = "繁體中文轉簡體中文"
        let converted = OpenCCBridge.shared.convertToSimplified(text)
        #expect(converted == "繁体中文转简体中文")
    }

    @Test("Test Simplified Chinese to Traditional Chinese")
    func testSC2TC()  {
        let text = "繁体中文转简体中文"
        let converted = OpenCCBridge.shared.convertToTraditional(text)
        #expect(converted == "繁體中文轉簡體中文")
    }

}
