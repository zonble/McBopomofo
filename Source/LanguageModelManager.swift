import Foundation
import Engine

class LanguageModelManagerSwift {

    static private let kUserOverrideModelCapacity = 500
    static private let kObservedOverrideHalflife = 5400.0 // 1.5hr

    static private var gLanguageModelMcBopomofo = Engine.McBopomofo.McBopomofoLM()
    static private var gLanguageModelPlainBopomofo = Engine.McBopomofo.McBopomofoLM()
    static private var gUserOverrideModel = Engine.McBopomofo.UserOverrideModel(kUserOverrideModelCapacity, kObservedOverrideHalflife)
    
    static private var kUserDataTemplateName = "template-data"
    static private var kExcludedPhrasesMcBopomofoTemplateName = "template-exclude-phrases"
    static private var kExcludedPhrasesPlainBopomofoTemplateName = "template-exclude-phrases-plain-bpmf"
    static private var kPhraseReplacementTemplateName = "template-phrases-replacement"
    static private var kTemplateExtension = ".txt"

    static private func LTLoadLanguageModelFile(filename filenameWithoutExtension: String, lm: Engine.McBopomofo.McBopomofoLM) {
        var lm = lm
        let cls = McBopomofoInputMethodController.self
        guard let path = Bundle(for: cls).path(forResource: filenameWithoutExtension, ofType: "txt") else {
         return
        }
        lm.loadLanguageModel(path.cString(using: .utf8))
    }

    static private func LTLoadAssociatedPhrases(lm: Engine.McBopomofo.McBopomofoLM) {
        var lm = lm
        let cls = McBopomofoInputMethodController.self
        guard let path = Bundle(for: cls).path(forResource: "associated-phrases", ofType: "txt") else {
            return
        }
        lm.loadLanguageModel(path.cString(using: .utf8))
    }

    static func loadDataModels () {
        if !gLanguageModelMcBopomofo.isDataModelLoaded() {
            LTLoadLanguageModelFile(filename: "data", lm: gLanguageModelMcBopomofo)
        }
        if !gLanguageModelPlainBopomofo.isDataModelLoaded() {
            LTLoadLanguageModelFile(filename: "data-plain-bpmf", lm: gLanguageModelPlainBopomofo)
        }
        if !gLanguageModelPlainBopomofo.isAssociatedPhrasesLoaded() {
            LTLoadAssociatedPhrases(lm: gLanguageModelPlainBopomofo)
        }
    }

    static func loadDataModel(mode:InputMode) {
        switch mode {
        case .bopomofo:
            if !gLanguageModelMcBopomofo.isDataModelLoaded() {
                LTLoadLanguageModelFile(filename: "data", lm: gLanguageModelMcBopomofo);
            }
        case .plainBopomofo:
            if !gLanguageModelPlainBopomofo.isDataModelLoaded() {
                LTLoadLanguageModelFile(filename: "data-plain-bpmf", lm: gLanguageModelPlainBopomofo)
            }
            if !gLanguageModelPlainBopomofo.isAssociatedPhrasesLoaded() {
                LTLoadAssociatedPhrases(lm: gLanguageModelPlainBopomofo)
            }
        default:
            break
        }

    }

    static func loadUserPhrases() {
        gLanguageModelMcBopomofo.loadUserPhrases(
            userPhrasesDataPathMcBopomofo.cString(using: .utf8),
            excludedPhrasesDataPathMcBopomofo.cString(using: .utf8)
        )
        gLanguageModelPlainBopomofo.loadUserPhrases(
            nil,
            excludedPhrasesDataPathPlainBopomofo.cString(using: .utf8)
        )
    }

    static func loadUserPhraseReplacement() {
        gLanguageModelMcBopomofo.loadPhraseReplacementMap(phraseReplacementDataPathMcBopomofo.cString(using: .utf8))
    }

    static func setupDataModelValueConverter() {
//        let converter:std.function = { input in
//
//        }
        let x: (String) -> Void = { x in }
        gLanguageModelMcBopomofo.setExternalConverter( x as std.function<String>))
    }

//
//    + (void)setupDataModelValueConverter
//    {
//        auto converter = [](std::string input) {
//            if (!Preferences.chineseConversionEnabled) {
//                return input;
//            }
//
//            if (Preferences.chineseConversionStyle == 0) {
//                return input;
//            }
//
//            NSString *text = [NSString stringWithUTF8String:input.c_str()];
//            if (Preferences.chineseConversionEngine == 1) {
//                text = [VXHanConvert convertToSimplifiedFrom:text];
//            } else {
//                text = [[OpenCCBridge sharedInstance] convertToSimplified:text];
//            }
//            return std::string(text.UTF8String);
//        };
//
//        gLanguageModelMcBopomofo.setExternalConverter(converter);
//        gLanguageModelPlainBopomofo.setExternalConverter(converter);
//    }



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
