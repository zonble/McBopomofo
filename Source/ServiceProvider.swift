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

import AppKit

class ServiceProvider: NSObject  {
    func extractReading(from firstWord:String) -> String {
        var matches: [String] = []

        // greedily find the longest possible matches
        var matchFrom = firstWord.startIndex
        while matchFrom < firstWord.endIndex {
            let substring = firstWord.suffix(from: matchFrom)
            let substringCount = substring.count

            // if an exact match fails, try dropping successive characters from the end to see
            // if we can find shorter matches
            var drop = 0
            while drop < substringCount {
                let candidate = String(substring.dropLast(drop))
                if let match = LanguageModelManager.reading(for: candidate) {
                    // append the match and skip over the matched portion
                    matches.append(match)
                    matchFrom = firstWord.index(matchFrom, offsetBy: substringCount - drop)
                    break
                }
                drop += 1
            }

            if drop >= substringCount {
                // didn't match anything?!
                matches.append("？")
                matchFrom = firstWord.index(matchFrom, offsetBy: 1)
            }
        }

        let reading = matches.joined(separator: "-")
        return reading
    }

    @objc func addUserPhrase(_ pasteboard: NSPasteboard, userData: String?, error: NSErrorPointer) {
        guard let string = pasteboard.string(forType: .string),
              let firstWord = string.components(separatedBy: .whitespacesAndNewlines).first
        else {
            return
        }

        if firstWord.isEmpty {
            return
        }

        let reading = extractReading(from: firstWord)

        if reading.isEmpty {
            return
        }

        LanguageModelManager.writeUserPhrase("\(firstWord) \(reading)")
        (NSApp.delegate as? AppDelegate)?.openUserPhrases(self)
    }

    @objc func addBopomofoAnnotations(_ pasteboard: NSPasteboard, userData: String?, error: NSErrorPointer) {

        func create(_ text: String, annotation: String) -> NSAttributedString {
            var null: Unmanaged<CFString>?
            var furigana: UnsafeMutablePointer<Unmanaged<CFString>?> = UnsafeMutablePointer<Unmanaged<CFString>?>.allocate(capacity: 4)
            furigana[0] = Unmanaged.passUnretained(annotation as CFString)
            furigana[1] = null
            furigana[2] = null
            furigana[3] = null
            let ruby = CTRubyAnnotationCreate(.auto, .auto, 0.5, furigana)
            let attrString = NSAttributedString(string: text, attributes: [
                .rubyAnnotation: ruby
            ])
            return attrString
        }

        guard let data = pasteboard.data(forType: .rtf),
              let attrString = NSAttributedString(docFormat: data, documentAttributes: nil) else {
            return
        }
        let string = attrString.string
        let output = NSMutableAttributedString()

        for c in string {
            let s = String(c)
            if let reading = LanguageModelManager.reading(for: s) {
                let attrString = create(s, annotation: reading)
                output.append(attrString)
            } else {
                output.append(NSAttributedString(string: s))
            }
        }
        pasteboard.declareTypes([.rtf], owner: nil)
        if let outputData = try? output.data(from: NSMakeRange(0, attrString.length)) {
            pasteboard.setData(outputData, forType: .rtf)
        }
    }

}

extension NSAttributedString.Key {
    static let rubyAnnotation: NSAttributedString.Key = kCTRubyAnnotationAttributeName as NSAttributedString.Key
}
