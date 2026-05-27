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

import Foundation

private let kUserDataTemplateName = "template-data"
private let kUserDataPlainBopomofoTemplateName = "template-data-plain-bpmf"
private let kExcludedPhrasesMcBopomofoTemplateName = "template-exclude-phrases"
private let kExcludedPhrasesPlainBopomofoTemplateName = "template-exclude-phrases-plain-bpmf"
private let kPhraseReplacementTemplateName = "template-phrases-replacement"
private let kTemplateExtension = ".txt"

@objc class LanguageModelManager: NSObject {

    // MARK: - C++ data model operations (delegated to bridge)

    @objc static func loadDataModels() {
        LanguageModelManagerBridge.loadDataModels()
    }

    @objc static func loadDataModel(_ mode: InputMode) {
        LanguageModelManagerBridge.loadDataModel(mode)
    }

    @objc(loadUserPhrasesWithPlainBopomofoEnabled:)
    static func loadUserPhrases(enableForPlainBopomofo userPhraseForPlainBopomofo: Bool) {
        LanguageModelManagerBridge.loadUserPhrases(
            withMcBopomofoPath: userPhrasesDataPathMcBopomofo,
            excludedMcBopomofoPath: excludedPhrasesDataPathMcBopomofo,
            plainBopomofoPath: userPhraseForPlainBopomofo ? userPhrasesDataPathPlainBopomofo : nil,
            excludedPlainBopomofoPath: excludedPhrasesDataPathPlainBopomofo
        )
    }

    @objc static func loadUserPhraseReplacement() {
        LanguageModelManagerBridge.loadUserPhraseReplacement(withPath: phraseReplacementDataPathMcBopomofo)
    }

    @objc static func setupDataModelValueConverter() {
        LanguageModelManagerBridge.setupDataModelValueConverter()
    }

    @objc static func checkIfExist(userPhrase: String, key: String) -> Bool {
        LanguageModelManagerBridge.checkIfExist(userPhrase: userPhrase, key: key)
    }

    @objc static var phraseReplacementEnabled: Bool {
        get { LanguageModelManagerBridge.phraseReplacementEnabled() }
        set { LanguageModelManagerBridge.setPhraseReplacementEnabled(newValue) }
    }

    @objc static func readingFor(_ phrase: String) -> String? {
        LanguageModelManagerBridge.reading(for: phrase)
    }

    @objc(annotateVariantForCharacters:readings:)
    static func annotateVariant(characters: String, readings: String) -> String {
        LanguageModelManagerBridge.annotateVariant(forCharacters: characters, readings: readings)
    }

    // MARK: - Foundation-only path operations

    @objc static var dataFolderPath: String {
        if Preferences.useCustomUserPhraseLocation {
            return Preferences.customUserPhraseLocation
        }
        return UserPhraseLocationHelper.defaultUserPhraseLocation()
    }

    @objc static var userPhrasesDataPathMcBopomofo: String {
        (dataFolderPath as NSString).appendingPathComponent("data.txt")
    }

    @objc static var userPhrasesDataPathPlainBopomofo: String {
        (dataFolderPath as NSString).appendingPathComponent("data-plain-bpmf.txt")
    }

    @objc static var excludedPhrasesDataPathMcBopomofo: String {
        (dataFolderPath as NSString).appendingPathComponent("exclude-phrases.txt")
    }

    @objc static var excludedPhrasesDataPathPlainBopomofo: String {
        (dataFolderPath as NSString).appendingPathComponent("exclude-phrases-plain-bpmf.txt")
    }

    @objc static var phraseReplacementDataPathMcBopomofo: String {
        (dataFolderPath as NSString).appendingPathComponent("phrases-replacement.txt")
    }

    // MARK: - User data folder management

    @objc static func checkIfUserDataFolderExists() -> Bool {
        let folderPath = dataFolderPath
        var isFolder: ObjCBool = false
        var folderExist = FileManager.default.fileExists(atPath: folderPath, isDirectory: &isFolder)
        if folderExist && !isFolder.boolValue {
            do {
                try FileManager.default.removeItem(atPath: folderPath)
            } catch {
                NSLog("Failed to remove folder %@", error.localizedDescription)
                return false
            }
            folderExist = false
        }
        if !folderExist {
            do {
                try FileManager.default.createDirectory(atPath: folderPath, withIntermediateDirectories: true, attributes: nil)
            } catch {
                NSLog("Failed to create folder %@", error.localizedDescription)
                return false
            }
        }
        return true
    }

    @objc static func ensureFileExists(_ filePath: String, populateWithTemplate templateBasename: String, extension ext: String) -> Bool {
        if !FileManager.default.fileExists(atPath: filePath) {
            let templateURL = Bundle.main.url(forResource: templateBasename, withExtension: ext)
            let templateData: Data
            if let url = templateURL, let data = try? Data(contentsOf: url) {
                templateData = data
            } else {
                templateData = Data()
            }
            let result = (templateData as NSData).write(toFile: filePath, atomically: true)
            if !result {
                NSLog("Failed to write file")
                return false
            }
        }
        return true
    }

    @objc static func checkIfUserLanguageModelFilesExist() -> Bool {
        guard checkIfUserDataFolderExists() else { return false }
        guard ensureFileExists(userPhrasesDataPathMcBopomofo, populateWithTemplate: kUserDataTemplateName, extension: kTemplateExtension) else { return false }
        guard ensureFileExists(userPhrasesDataPathPlainBopomofo, populateWithTemplate: kUserDataPlainBopomofoTemplateName, extension: kTemplateExtension) else { return false }
        guard ensureFileExists(excludedPhrasesDataPathMcBopomofo, populateWithTemplate: kExcludedPhrasesMcBopomofoTemplateName, extension: kTemplateExtension) else { return false }
        guard ensureFileExists(excludedPhrasesDataPathPlainBopomofo, populateWithTemplate: kExcludedPhrasesPlainBopomofoTemplateName, extension: kTemplateExtension) else { return false }
        guard ensureFileExists(phraseReplacementDataPathMcBopomofo, populateWithTemplate: kPhraseReplacementTemplateName, extension: kTemplateExtension) else { return false }
        return true
    }

    @objc static func writeUserPhrase(_ userPhrase: String) -> Bool {
        guard checkIfUserLanguageModelFilesExist() else { return false }

        let excludePath = excludedPhrasesDataPathMcBopomofo
        _removePhrase(userPhrase, atPath: excludePath)

        let includePath = userPhrasesDataPathMcBopomofo
        if _checkIfPhrase(userPhrase, existAtPath: includePath) {
            return false
        }
        return _writePhrase(userPhrase, atEndOfPath: includePath)
    }

    @objc static func removeUserPhrase(_ userPhrase: String) -> Bool {
        guard checkIfUserLanguageModelFilesExist() else { return false }

        let includePath = userPhrasesDataPathMcBopomofo
        _removePhrase(userPhrase, atPath: includePath)

        let excludePath = excludedPhrasesDataPathMcBopomofo
        if _checkIfPhrase(userPhrase, existAtPath: excludePath) {
            return false
        }
        return _writePhrase(userPhrase, atEndOfPath: excludePath)
    }

    // MARK: - Private helpers

    @objc static func _checkIfPhrase(_ phrase: String, existAtPath path: String) -> Bool {
        let components = phrase.components(separatedBy: " ")
        guard components.count == 2 else { return false }
        let exactPhrase = components[0]
        let key = components[1]

        guard FileManager.default.fileExists(atPath: path) else { return false }
        guard let content = try? String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8) else { return false }

        for line in content.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let lineComponents = trimmed.components(separatedBy: " ")
            guard lineComponents.count == 2 else { continue }
            if lineComponents[0] == exactPhrase && lineComponents[1] == key {
                return true
            }
        }
        return false
    }

    @objc static func _writePhrase(_ phrase: String, atEndOfPath path: String) -> Bool {
        var addLineBreakAtFront = false
        if FileManager.default.fileExists(atPath: path),
           let attr = try? FileManager.default.attributesOfItem(atPath: path),
           let fileSize = attr[.size] as? UInt64, fileSize > 0,
           let readFile = FileHandle(forReadingAtPath: path) {
            readFile.seek(toFileOffset: fileSize - 1)
            let data = readFile.readDataToEndOfFile()
            if let byte = data.first, byte != UInt8(ascii: "\n") {
                addLineBreakAtFront = true
            }
            readFile.closeFile()
        }

        var currentMarkedPhrase = ""
        if addLineBreakAtFront {
            currentMarkedPhrase += "\n"
        }
        currentMarkedPhrase += phrase
        currentMarkedPhrase += "\n"

        guard let writeFile = FileHandle(forUpdatingAtPath: path) else { return false }
        writeFile.seekToEndOfFile()
        if let data = currentMarkedPhrase.data(using: .utf8) {
            writeFile.write(data)
        }
        writeFile.closeFile()
        return true
    }

    @objc static func _removePhrase(_ phrase: String, atPath path: String) -> Bool {
        let components = phrase.components(separatedBy: " ")
        guard components.count == 2 else { return false }
        let exactPhrase = components[0]
        let key = components[1]

        guard FileManager.default.fileExists(atPath: path) else { return false }
        guard let content = try? String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8) else { return false }

        var result = false
        var mutableString = ""
        for line in content.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let lineComponents = trimmed.components(separatedBy: " ")
            if lineComponents.count == 2 && lineComponents[0] == exactPhrase && lineComponents[1] == key {
                result = true
                continue
            }
            mutableString += line
            mutableString += "\n"
        }
        if result {
            do {
                try mutableString.write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
            } catch {
                return false
            }
            return true
        }
        return false
    }
}
