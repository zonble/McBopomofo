import Foundation
import Engine

class LanguageModelManagerSwift {

    static var dataFolderPath: String {
        let useCustomLocation = Preferences.useCustomUserPhraseLocation
        if !useCustomLocation {
            return UserPhraseLocationHelper.defaultUserPhraseLocation
        }
        return Preferences.customUserPhraseLocation;
    }

    static var userPhrasesDataPathMcBopomofo: String {
        (dataFolderPath as NSString).appendingPathComponent("data.txt")
    }

    static var excludedPhrasesDataPathMcBopomofo: String {
        (dataFolderPath as NSString).appendingPathComponent("exclude-phrases.txt")
    }

    static var excludedPhrasesDataPathPlainBopomofo: String {
        (dataFolderPath as NSString).appendingPathComponent("exclude-phrases-plain-bpmf.txt")
    }

    static var phraseReplacementDataPathMcBopomofo: String {
        (dataFolderPath as NSString).appendingPathComponent("phrases-replacement.txt")
    }

    static var phraseReplacementEnabled: Bool {
//        var test: std.string = "test"
        return false
//        return gLanguageModelMcBopomofo.phraseReplacementEnabled()
    }




}
