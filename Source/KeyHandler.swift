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

import CandidateUI
import Foundation

// MARK: - KeyHandlerDelegate

@objc protocol KeyHandlerDelegate: NSObjectProtocol {
    func candidateController(for keyHandler: KeyHandler) -> Any
    func keyHandler(
        _ keyHandler: KeyHandler, didSelectCandidateAt index: Int, candidateController controller: Any
    )
    @discardableResult
    func keyHandler(_ keyHandler: KeyHandler, didRequestWriteUserPhraseWith state: InputState)
        -> Bool
    @discardableResult
    func keyHandler(
        _ keyHandler: KeyHandler, didRequestBoostScoreForPhrase phrase: String, reading: String
    ) -> Bool
    @discardableResult
    func keyHandler(
        _ keyHandler: KeyHandler, didRequestExcludePhrase phrase: String, reading: String
    ) -> Bool
    @discardableResult
    func keyHandlerDidRequestReloadLanguageModel(_ keyHandler: KeyHandler) -> Bool
}

// MARK: - KeyHandler

@objc class KeyHandler: NSObject {
    private let bridge = KeyHandlerCxxBridge()
    @objc weak var delegate: (any KeyHandlerDelegate)?

    @objc var inputMode: InputMode {
        get { bridge.inputMode }
        set { bridge.inputMode = newValue }
    }

    @objc var actualCandidateCursorIndex: Int {
        Int(bridge.actualCandidateCursorIndex)
    }

    @objc var cursorIndex: Int {
        Int(bridge.cursorIndex)
    }

    @objc func syncWithPreferences() {
        bridge.syncWithPreferences()
    }

    @objc func clear() {
        bridge.clear()
    }

    @objc func collectUserFileIssues() -> [String] {
        bridge.collectUserFileIssues()
    }

    @objc func buildInputtingState() -> InputState {
        bridge.buildInputtingState()
    }

    @objc func buildAssociatedPhrasePlainState(
        withReading reading: String, value: String, useVerticalMode: Bool
    ) -> InputState? {
        bridge.buildAssociatedPhrasePlainState(
            withReading: reading, value: value, useVerticalMode: useVerticalMode)
    }

    @objc func fixNode(
        reading: String, value: String, originalCursorIndex: Int,
        useMoveCursorAfterSelectionSetting: Bool
    ) {
        bridge.fixNode(
            reading: reading, value: value, originalCursorIndex: originalCursorIndex,
            useMoveCursorAfterSelectionSetting: useMoveCursorAfterSelectionSetting)
    }

    @objc func fixNodeForAssociatedPhraseWithPrefix(
        at index: Int, prefixReading: String, prefixValue: String,
        associatedPhraseReading: String, associatedPhraseValue: String
    ) {
        bridge.fixNodeForAssociatedPhraseWithPrefix(
            at: index, prefixReading: prefixReading, prefixValue: prefixValue,
            associatedPhraseReading: associatedPhraseReading,
            associatedPhraseValue: associatedPhraseValue)
    }

    @discardableResult
    @objc func handleAssociatedPhrase(
        with state: InputState, useVerticalMode: Bool,
        stateCallback: @escaping (InputState) -> Void,
        errorCallback: @escaping () -> Void,
        autoTriggered: Bool,
        maxCandidateCount: Int
    ) -> Bool {
        bridge.handleAssociatedPhrase(
            with: state, useVerticalMode: useVerticalMode,
            stateCallback: stateCallback, errorCallback: errorCallback,
            autoTriggered: autoTriggered, maxCandidateCount: maxCandidateCount)
    }

    @objc func computeActualCursorIndex(_ cursor: Int) -> Int {
        Int(bridge.computeActualCursorIndex(cursor))
    }

    @objc func buildAssociatedPhraseStateWithParams(_ params: BuildAssociatedPhraseParams)
        -> InputState?
    {
        bridge.buildAssociatedPhraseStateWithParams(params)
    }

    @objc func handleForceCommit(stateCallback: @escaping (InputState) -> Void) {
        if bridge.bpmfReadingBufferIsEmpty && bridge.gridLength == 0 {
            return
        }
        bridge.bpmfReadingBufferClear()
        let inputting = bridge.buildInputtingState()
        bridge.clear()
        let committing = InputState.Committing(poppedText: inputting.composingBuffer)
        stateCallback(committing)
    }

    @discardableResult
    @objc func handle(
        input: KeyHandlerInput, state inState: InputState,
        stateCallback: @escaping (InputState) -> Void,
        errorCallback: @escaping () -> Void
    ) -> Bool {
        var state = inState
        let charCode = input.charCode
        let emacsKey = input.emacsKey

        // MARK: Handle Selecting Feature
        if state is InputState.SelectingFeature || state is InputState.SelectingDateMacro
            || state is InputState.IrohaKanaCandidates
        {
            return handleCandidateState(
                state: state, input: input, stateCallback: stateCallback,
                errorCallback: errorCallback)
        }

        // MARK: Handle Big5 Input
        if state is InputState.Big5 {
            return handleBig5State(
                state: state, input: input, stateCallback: stateCallback,
                errorCallback: errorCallback)
        }

        // MARK: Handle Iroha Japanese Kana Input
        if state is InputState.IrohaKana {
            return handleIrohaKanaState(
                state: state, input: input, stateCallback: stateCallback,
                errorCallback: errorCallback)
        }

        // MARK: Handle Chinese Number Input
        if state is InputState.Number {
            let result = handleNumberState(
                state: state, input: input, stateCallback: stateCallback,
                errorCallback: errorCallback)
            if !result {
                let numberState = state as! InputState.Number
                if numberState.candidates.isEmpty {
                    return true
                }
                handleCandidateState(
                    state: state, input: input, stateCallback: stateCallback,
                    errorCallback: errorCallback)
            }
            return true
        }

        // if the inputText is empty, it's a function key combination, we ignore it
        if input.inputText.isEmpty {
            return false
        }

        // if the composing buffer is empty and there's no reading, and there is some
        // function key combination, we ignore it
        let isFunctionKey =
            (input.isCommandHold || input.isOptionHold || input.isNumericPad)
            || input.isControlHotKey
        let isAutoTriggeredAssociated =
            (state is InputState.AssociatedPhrases)
            && (state as! InputState.AssociatedPhrases).autoTriggered
        if !(state is InputState.NotEmpty) && !(state is InputState.AssociatedPhrasesPlain)
            && !isAutoTriggeredAssociated && isFunctionKey
        {
            return false
        }

        // Caps Lock processing: if Caps Lock is on, temporarily disable bopomofo.
        if charCode == 8 || charCode == 13 || input.isAbsorbedArrowKey
            || input.isExtraChooseCandidateKey || input.isCursorForward || input.isCursorBackward
        {
            // do nothing if backspace is pressed -- we ignore the key
        } else if input.isCapsLockOn {
            clear()
            let emptyState = InputState.Empty()
            stateCallback(emptyState)

            if input.isShiftHold {
                return false
            }

            if charCode < 0x80 && !isprint(Int32(charCode)) {
                return false
            }

            let committingState = InputState.Committing(
                poppedText: input.inputText.lowercased())
            stateCallback(committingState)
            stateCallback(emptyState)
            return true
        }

        if input.isNumericPad && !Preferences.selectCandidateWithNumericKeypad {
            if !input.isLeft && !input.isRight && !input.isDown && !input.isUp
                && charCode != 32 && isprint(Int32(charCode)) != 0
            {
                clear()
                let emptyState = InputState.Empty()
                stateCallback(emptyState)
                let committing = InputState.Committing(poppedText: input.inputText.lowercased())
                stateCallback(committing)
                stateCallback(emptyState)
                return true
            }
        }

        // MARK: Handle Associated Phrases
        if state is InputState.AssociatedPhrasesPlain {
            let result = handleCandidateState(
                state: state, input: input, stateCallback: stateCallback,
                errorCallback: errorCallback)
            if result {
                return true
            }
            state = InputState.Empty()
            stateCallback(state)
        }

        if state is InputState.AssociatedPhrases {
            let result = handleCandidateState(
                state: state, input: input, stateCallback: stateCallback,
                errorCallback: errorCallback)
            if result {
                return true
            }
            if (state as! InputState.AssociatedPhrases).autoTriggered {
                state = bridge.buildInputtingState()
                stateCallback(state)
            } else {
                return true
            }
        }

        // MARK: Handle Candidates
        if state is InputState.ChoosingCandidate {
            return handleCandidateState(
                state: state, input: input, stateCallback: stateCallback,
                errorCallback: errorCallback)
        }

        // MARK: Handle Other States with Menu
        if state is InputState.SelectingDictionary || state is InputState.ShowingCharInfo
            || state is InputState.CustomMenu
        {
            return handleCandidateState(
                state: state, input: input, stateCallback: stateCallback,
                errorCallback: errorCallback)
        }

        // MARK: Handle Marking
        if let marking = state as? InputState.Marking {
            if handleMarkingState(
                state: marking, input: input, stateCallback: stateCallback,
                errorCallback: errorCallback)
            {
                return true
            }
            state = marking.convertToInputting()
            stateCallback(state)
        }

        var keyConsumedByReading = false
        let skipBpmfHandling = input.isReservedKey || input.isControlHold

        // MARK: Handle BPMF Keys
        let isValidKey = bridge.bpmfReadingBufferIsValidKey(charCode)
        if !skipBpmfHandling && isValidKey {
            bridge.bpmfReadingBufferCombineKey(charCode)
            keyConsumedByReading = true

            if !bridge.bpmfReadingBufferHasToneMarker {
                stateCallback(bridge.buildInputtingState())
                return true
            }
        }

        // Issue 753: allow tone key to change an existing reading before the cursor.
        if let inputting = bridge.tryChangePriorTone(withCharCode: charCode) {
            stateCallback(inputting)
            return true
        }

        var composeReading =
            isValidKey && bridge.bpmfReadingBufferHasToneMarker
            && !bridge.bpmfReadingBufferHasToneMarkerOnly

        composeReading =
            composeReading
            || (!bridge.bpmfReadingBufferIsEmpty && (charCode == 32 || charCode == 13))

        if composeReading {
            let reading = bridge.bpmfComposedReading()

            if !bridge.hasUnigrams(reading) {
                errorCallback()

                if Preferences.keepReadingUponCompositionError {
                    stateCallback(bridge.buildInputtingState())
                    return true
                }

                bridge.bpmfReadingBufferClear()
                if bridge.gridLength == 0 {
                    stateCallback(InputState.EmptyIgnoringPreviousState())
                } else {
                    stateCallback(bridge.buildInputtingState())
                }
                return true
            }

            bridge.gridInsertReading(reading)
            bridge.walk()

            if inputMode != .plainBopomofo {
                bridge.applyUserOverrideModelAfterWalk()
            }

            bridge.bpmfReadingBufferClear()

            let inputting = bridge.buildInputtingState()
            stateCallback(inputting)

            if inputMode == .bopomofo && Preferences.associatedPhrasesEnabled {
                bridge.handleAssociatedPhrase(
                    with: inputting, useVerticalMode: input.useVerticalMode,
                    stateCallback: stateCallback, errorCallback: errorCallback,
                    autoTriggered: true, maxCandidateCount: 2)
            } else if inputMode == .plainBopomofo {
                let choosingCandidates = bridge.buildCandidateStateFromInputtingState(
                    inputting, useVerticalMode: input.useVerticalMode)

                if choosingCandidates.candidates.count == 1 {
                    clear()
                    let text = choosingCandidates.candidates.first!.value
                    let candidateReading = choosingCandidates.candidates.first!.reading
                    stateCallback(InputState.Committing(poppedText: text))

                    if !Preferences.associatedPhrasesEnabled {
                        stateCallback(InputState.Empty())
                    } else {
                        let associatedPhrases = bridge.buildAssociatedPhrasePlainState(
                            withReading: candidateReading, value: text,
                            useVerticalMode: input.useVerticalMode)
                        if let phrases = associatedPhrases {
                            stateCallback(phrases)
                        } else {
                            stateCallback(InputState.Empty())
                        }
                    }
                } else {
                    stateCallback(choosingCandidates)
                }
            }

            return true
        }

        if keyConsumedByReading {
            stateCallback(bridge.buildInputtingState())
            return true
        }

        // MARK: Space and Down
        if bridge.bpmfReadingBufferIsEmpty && (state is InputState.NotEmpty)
            && (input.isExtraChooseCandidateKey || charCode == 32
                || (input.useVerticalMode && input.isVerticalModeOnlyChooseCandidateKey))
        {
            if charCode == 32 {
                if input.isShiftHold || !Preferences.chooseCandidateUsingSpace {
                    if bridge.gridCursor >= bridge.gridLength {
                        let composingBuffer = (state as! InputState.NotEmpty).composingBuffer
                        if !composingBuffer.isEmpty {
                            stateCallback(InputState.Committing(poppedText: composingBuffer))
                        }
                        clear()
                        stateCallback(InputState.Committing(poppedText: " "))
                        stateCallback(InputState.Empty())
                    } else if bridge.hasUnigrams(" ") {
                        bridge.gridInsertReading(" ")
                        bridge.walk()
                        stateCallback(bridge.buildInputtingState())
                    }
                    return true
                }
            }

            let originalCursorIndex = bridge.gridCursor

            if originalCursorIndex == bridge.gridLength
                && Preferences.selectPhraseAfterCursorAsCandidate
                && Preferences.moveCursorAfterSelectingCandidate
            {
                bridge.gridCursor = originalCursorIndex - 1
            }
            let choosingCandidates = bridge.buildCandidateStateFromInputtingState(
                bridge.buildInputtingState(), useVerticalMode: input.useVerticalMode)
            choosingCandidates.originalCursorIndex = originalCursorIndex
            stateCallback(choosingCandidates)
            return true
        }

        // MARK: Esc
        if charCode == 27 {
            return handleEscState(
                state: state, stateCallback: stateCallback, errorCallback: errorCallback)
        }

        // MARK: Tab
        if input.isTab {
            return bridge.handleTab(
                withState: state, shiftIsHold: input.isShiftHold, stateCallback: stateCallback,
                errorCallback: errorCallback)
        }

        // MARK: Cursor backward
        if input.isCursorBackward || emacsKey == .backward {
            return handleBackwardState(
                state: state, input: input, stateCallback: stateCallback,
                errorCallback: errorCallback)
        }

        // MARK: Cursor forward
        if input.isCursorForward || emacsKey == .forward {
            return handleForwardState(
                state: state, input: input, stateCallback: stateCallback,
                errorCallback: errorCallback)
        }

        // MARK: Home
        if input.isHome || emacsKey == .home {
            return handleHomeState(
                state: state, stateCallback: stateCallback, errorCallback: errorCallback)
        }

        // MARK: End
        if input.isEnd || emacsKey == .end {
            return handleEndState(
                state: state, stateCallback: stateCallback, errorCallback: errorCallback)
        }

        // MARK: AbsorbedArrowKey
        if input.isAbsorbedArrowKey || input.isExtraChooseCandidateKey {
            return handleAbsorbedArrowKeyState(
                state: state, stateCallback: stateCallback, errorCallback: errorCallback)
        }

        // MARK: Backspace
        if charCode == 8 {
            return handleBackspaceState(
                state: state, stateCallback: stateCallback, errorCallback: errorCallback)
        }

        // MARK: Delete
        if input.isDelete || emacsKey == .delete {
            return handleDeleteState(
                state: state, stateCallback: stateCallback, errorCallback: errorCallback)
        }

        // MARK: Enter
        if charCode == 13 {
            if inputMode == .bopomofo && input.isControlHold {
                let string: String
                if Preferences.controlEnterOutput == .off {
                    errorCallback()
                    return true
                }
                switch Preferences.controlEnterOutput {
                case .bpmfReading:
                    string = bridge.currentBpmfReading()
                case .htmlRuby:
                    string = bridge.currentHtmlRuby()
                case .brailleUnicode:
                    string = bridge.currentBraille(withType: BrailleType.unicode.rawValue)
                case .brailleAscii:
                    string = bridge.currentBraille(withType: BrailleType.ascii.rawValue)
                case .hanyuPinyin:
                    string = bridge.currentHanyuPinyin()
                default:
                    string = ""
                }
                clear()
                stateCallback(InputState.Committing(poppedText: string))
                stateCallback(InputState.Empty())
                return true
            }
            if Preferences.shiftEnterEnabled && inputMode == .bopomofo && input.isShiftHold
                && state is InputState.Inputting
            {
                return bridge.handleAssociatedPhrase(
                    with: state, useVerticalMode: input.useVerticalMode,
                    stateCallback: stateCallback, errorCallback: errorCallback,
                    autoTriggered: false, maxCandidateCount: 0)
            }
            return handleEnterState(
                state: state, stateCallback: stateCallback, errorCallback: errorCallback)
        }

        // MARK: Enter Big5 code mode
        if input.isControlHold && charCode == UInt16(("'" as UnicodeScalar).value) /* backtick */ {
            if Preferences.big5InputEnabled {
                clear()
                if let inputting = state as? InputState.Inputting {
                    stateCallback(InputState.Committing(poppedText: inputting.composingBuffer))
                }
                stateCallback(InputState.Big5(code: ""))
                return true
            }
        }

        // keyCode 42 = backslash on US keyboard
        if input.isControlHold && input.keyCode == 42 {
            clear()
            if let inputting = state as? InputState.Inputting {
                stateCallback(InputState.Committing(poppedText: inputting.composingBuffer))
            }
            stateCallback(InputState.SelectingFeature())
            return true
        }

        // MARK: Punctuation list
        let backQuoteChar = UInt16((("`" as UnicodeScalar).value))
        if charCode == backQuoteChar && !(input.isControlHold || input.isCommandHold || input.isOptionHold)
        {
            if bridge.hasUnigrams("_punctuation_list") {
                if bridge.bpmfReadingBufferIsEmpty {
                    bridge.gridInsertReading("_punctuation_list")
                    bridge.walk()
                    let originalCursorIndex = bridge.gridCursor
                    if Preferences.selectPhraseAfterCursorAsCandidate {
                        bridge.gridCursor = originalCursorIndex - 1
                    }
                    let choosingCandidate = bridge.buildCandidateStateFromInputtingState(
                        bridge.buildInputtingState(), useVerticalMode: input.useVerticalMode)
                    let choosingPunctuationList = InputState.ChoosingPunctuationList(
                        choosingCandidate: choosingCandidate)
                    choosingPunctuationList.originalCursorIndex = originalCursorIndex
                    stateCallback(choosingPunctuationList)
                } else {
                    errorCallback()
                }
                return true
            }
        }

        // MARK: Punctuation
        let punctuationNamePrefix: String
        if input.isControlHold {
            punctuationNamePrefix = "_ctrl_punctuation_"
        } else if Preferences.halfWidthPunctuationEnabled {
            punctuationNamePrefix = "_half_punctuation_"
        } else {
            punctuationNamePrefix = "_punctuation_"
        }
        let layout = bridge.currentLayout()
        let charStr = String(format: "%c", charCode)
        let customPunctuation = punctuationNamePrefix + layout + charStr
        if bridge.handlePunctuation(
            customPunctuation, state: state, useVerticalMode: input.useVerticalMode,
            stateCallback: stateCallback, errorCallback: errorCallback)
        {
            return true
        }

        let punctuation = punctuationNamePrefix + charStr
        if bridge.handlePunctuation(
            punctuation, state: state, useVerticalMode: input.useVerticalMode,
            stateCallback: stateCallback, errorCallback: errorCallback)
        {
            return true
        }

        if charCode >= UInt16(("A" as UnicodeScalar).value) && charCode <= UInt16(("Z" as UnicodeScalar).value)
        {
            if Preferences.letterBehavior == 1 {
                let letter = "_letter_" + charStr
                if bridge.handlePunctuation(
                    letter, state: state, useVerticalMode: input.useVerticalMode,
                    stateCallback: stateCallback, errorCallback: errorCallback)
                {
                    return true
                }
            } else {
                if state is InputState.NotEmpty {
                    clear()
                    let empty = InputState.Empty()
                    stateCallback(empty)
                    state = empty
                }
            }
        }

        // still nothing
        if state is InputState.NotEmpty || !bridge.bpmfReadingBufferIsEmpty {
            errorCallback()
            stateCallback(state)
            return true
        }

        return false
    }
}

// MARK: - Private handle methods

extension KeyHandler {

    private func handleEscState(
        state: InputState, stateCallback: (InputState) -> Void,
        errorCallback: () -> Void
    ) -> Bool {
        if !(state is InputState.Inputting) {
            return false
        }

        if Preferences.escToCleanInputBuffer {
            clear()
            stateCallback(InputState.EmptyIgnoringPreviousState())
        } else {
            if !bridge.bpmfReadingBufferIsEmpty {
                bridge.bpmfReadingBufferClear()
                if bridge.gridLength == 0 {
                    stateCallback(InputState.EmptyIgnoringPreviousState())
                } else {
                    stateCallback(bridge.buildInputtingState())
                }
            }
        }
        return true
    }

    private func handleBackwardState(
        state: InputState, input: KeyHandlerInput,
        stateCallback: (InputState) -> Void, errorCallback: () -> Void
    ) -> Bool {
        if !(state is InputState.Inputting) {
            return false
        }

        if !bridge.bpmfReadingBufferIsEmpty {
            errorCallback()
            stateCallback(state)
            return true
        }

        var currentState = state as! InputState.Inputting

        if input.isShiftHold {
            if currentState.cursorIndex > 0 {
                if Preferences.bopomofoFontAnnotationSupportEnabled {
                    currentState = inputtingStateWithMarkingStateUnsupportedTooltip(
                        state: currentState)
                    errorCallback()
                    stateCallback(currentState)
                } else {
                    let previousPosition = currentState.composingBuffer.previousUtf16Position(
                        for: Int(currentState.cursorIndex))
                    let marking = InputState.Marking(
                        composingBuffer: currentState.composingBuffer,
                        cursorIndex: currentState.cursorIndex,
                        markerIndex: UInt(previousPosition),
                        readings: bridge.currentReadings())
                    marking.tooltipForInputting = currentState.tooltip
                    stateCallback(marking)
                }
            } else {
                errorCallback()
                stateCallback(state)
            }
        } else {
            if bridge.gridCursor > 0 {
                bridge.gridCursor = bridge.gridCursor - 1
                stateCallback(bridge.buildInputtingState())
            } else {
                errorCallback()
                stateCallback(state)
            }
        }
        return true
    }

    private func handleForwardState(
        state: InputState, input: KeyHandlerInput,
        stateCallback: (InputState) -> Void, errorCallback: () -> Void
    ) -> Bool {
        if !(state is InputState.Inputting) {
            return false
        }

        if !bridge.bpmfReadingBufferIsEmpty {
            errorCallback()
            stateCallback(state)
            return true
        }

        var currentState = state as! InputState.Inputting

        if input.isShiftHold {
            if currentState.cursorIndex < currentState.composingBuffer.utf16.count {
                if Preferences.bopomofoFontAnnotationSupportEnabled {
                    currentState = inputtingStateWithMarkingStateUnsupportedTooltip(
                        state: currentState)
                    errorCallback()
                    stateCallback(currentState)
                } else {
                    let nextPosition = currentState.composingBuffer.nextUtf16Position(
                        for: Int(currentState.cursorIndex))
                    let marking = InputState.Marking(
                        composingBuffer: currentState.composingBuffer,
                        cursorIndex: currentState.cursorIndex,
                        markerIndex: UInt(nextPosition),
                        readings: bridge.currentReadings())
                    marking.tooltipForInputting = currentState.tooltip
                    stateCallback(marking)
                }
            } else {
                errorCallback()
                stateCallback(state)
            }
        } else {
            if bridge.gridCursor < bridge.gridLength {
                bridge.gridCursor = bridge.gridCursor + 1
                stateCallback(bridge.buildInputtingState())
            } else {
                errorCallback()
                stateCallback(state)
            }
        }
        return true
    }

    private func handleHomeState(
        state: InputState, stateCallback: (InputState) -> Void, errorCallback: () -> Void
    ) -> Bool {
        if !(state is InputState.Inputting) {
            return false
        }

        if !bridge.bpmfReadingBufferIsEmpty {
            errorCallback()
            stateCallback(state)
            return true
        }

        if bridge.gridCursor != 0 {
            bridge.gridCursor = 0
            stateCallback(bridge.buildInputtingState())
        } else {
            errorCallback()
            stateCallback(state)
        }
        return true
    }

    private func handleEndState(
        state: InputState, stateCallback: (InputState) -> Void, errorCallback: () -> Void
    ) -> Bool {
        if !(state is InputState.Inputting) {
            return false
        }

        if !bridge.bpmfReadingBufferIsEmpty {
            errorCallback()
            stateCallback(state)
            return true
        }

        if bridge.gridCursor != bridge.gridLength {
            bridge.gridCursor = bridge.gridLength
            stateCallback(bridge.buildInputtingState())
        } else {
            errorCallback()
            stateCallback(state)
        }
        return true
    }

    private func handleAbsorbedArrowKeyState(
        state: InputState, stateCallback: (InputState) -> Void, errorCallback: () -> Void
    ) -> Bool {
        if !(state is InputState.Inputting) {
            return false
        }

        if !bridge.bpmfReadingBufferIsEmpty {
            errorCallback()
        }
        stateCallback(state)
        return true
    }

    private func handleBackspaceState(
        state: InputState, stateCallback: (InputState) -> Void, errorCallback: () -> Void
    ) -> Bool {
        if !(state is InputState.Inputting) {
            return false
        }

        if bridge.bpmfReadingBufferHasToneMarkerOnly {
            bridge.bpmfReadingBufferClear()
        } else if bridge.bpmfReadingBufferIsEmpty {
            if bridge.gridCursor != 0 {
                bridge.gridDeleteReadingBeforeCursor()
                bridge.walk()
            } else {
                errorCallback()
                stateCallback(state)
                return true
            }
        } else {
            bridge.bpmfReadingBufferBackspace()
        }

        if bridge.bpmfReadingBufferIsEmpty && bridge.gridLength == 0 {
            stateCallback(InputState.EmptyIgnoringPreviousState())
        } else {
            stateCallback(bridge.buildInputtingState())
        }
        return true
    }

    private func handleDeleteState(
        state: InputState, stateCallback: (InputState) -> Void, errorCallback: () -> Void
    ) -> Bool {
        if !(state is InputState.Inputting) {
            return false
        }

        if bridge.bpmfReadingBufferIsEmpty {
            if bridge.gridCursor != bridge.gridLength {
                bridge.gridDeleteReadingAfterCursor()
                bridge.walk()
                let inputting = bridge.buildInputtingState()
                if inputting.composingBuffer.isEmpty {
                    stateCallback(InputState.EmptyIgnoringPreviousState())
                } else {
                    stateCallback(inputting)
                }
            } else {
                errorCallback()
                stateCallback(state)
            }
        } else {
            errorCallback()
            stateCallback(state)
        }
        return true
    }

    private func handleEnterState(
        state: InputState, stateCallback: (InputState) -> Void, errorCallback: () -> Void
    ) -> Bool {
        if !(state is InputState.Inputting) {
            return false
        }

        clear()
        let current = state as! InputState.Inputting
        stateCallback(InputState.Committing(poppedText: current.composingBuffer))
        stateCallback(InputState.Empty())
        return true
    }

    @discardableResult
    private func handleMarkingState(
        state: InputState.Marking, input: KeyHandlerInput,
        stateCallback: (InputState) -> Void, errorCallback: () -> Void
    ) -> Bool {
        let charCode = input.charCode

        if charCode == 27 {
            stateCallback(bridge.buildInputtingState())
            return true
        }

        if charCode == 13 {
            if !(delegate?.keyHandler(self, didRequestWriteUserPhraseWith: state) ?? false) {
                errorCallback()
                return true
            }
            stateCallback(bridge.buildInputtingState())
            return true
        }

        if input.inputText == "?" {
            if state.markedRange.length > 0 {
                let newState = InputState.SelectingDictionary(
                    previousState: state, selectedString: state.selectedText, selectedIndex: 0)
                stateCallback(newState)
                return true
            }
        }

        // Shift + left
        if (input.isCursorBackward || input.emacsKey == .backward) && input.isShiftHold {
            var index = Int(state.markerIndex)
            if index > 0 {
                index = state.composingBuffer.previousUtf16Position(for: index)
                let marking = InputState.Marking(
                    composingBuffer: state.composingBuffer, cursorIndex: state.cursorIndex,
                    markerIndex: UInt(index), readings: state.readings)
                marking.tooltipForInputting = state.tooltipForInputting
                if marking.markedRange.length == 0 {
                    stateCallback(marking.convertToInputting())
                } else {
                    stateCallback(marking)
                }
            } else {
                errorCallback()
                stateCallback(state)
            }
            return true
        }

        // Shift + right
        if (input.isCursorForward || input.emacsKey == .forward) && input.isShiftHold {
            var index = Int(state.markerIndex)
            if index < state.composingBuffer.utf16.count {
                index = state.composingBuffer.nextUtf16Position(for: index)
                let marking = InputState.Marking(
                    composingBuffer: state.composingBuffer, cursorIndex: state.cursorIndex,
                    markerIndex: UInt(index), readings: state.readings)
                marking.tooltipForInputting = state.tooltipForInputting
                if marking.markedRange.length == 0 {
                    stateCallback(marking.convertToInputting())
                } else {
                    stateCallback(marking)
                }
            } else {
                errorCallback()
                stateCallback(state)
            }
            return true
        }

        return false
    }

    @discardableResult
    private func handleCandidateState(
        state: InputState, input: KeyHandlerInput,
        stateCallback: @escaping (InputState) -> Void,
        errorCallback: @escaping () -> Void
    ) -> Bool {
        let inputText = input.inputText
        let charCode = input.charCode
        let gCurrentCandidateController =
            delegate?.candidateController(for: self) as? VTCandidateController

        // Handle auto-triggered associated phrases
        if let assocState = state as? InputState.AssociatedPhrases, assocState.autoTriggered {
            if input.isTab {
                let expanded = assocState.toggle(withAutoTriggered: false)
                stateCallback(expanded)
                return true
            }
            if input.isShiftHold && (charCode == 13 || input.isEnter) {
                let idx = Int(gCurrentCandidateController?.selectedCandidateIndex ?? 0)
                delegate?.keyHandler(
                    self, didSelectCandidateAt: idx,
                    candidateController: gCurrentCandidateController as Any)
                return true
            }
            return false
        }

        // Handle InputChoosingPunctuationList (backtick selection)
        if state is InputState.ChoosingPunctuationList {
            if inputText == "`" {
                if Preferences.selectPhraseAfterCursorAsCandidate {
                    bridge.gridDeleteReadingAfterCursor()
                } else {
                    bridge.gridDeleteReadingBeforeCursor()
                }
                bridge.walk()
                if bridge.gridLength > 0 {
                    handleForceCommit(stateCallback: stateCallback)
                } else {
                    stateCallback(InputState.EmptyIgnoringPreviousState())
                }
                stateCallback(InputState.SelectingFeature())
                return true
            }

            let key = "_punctuation_list_" + inputText
            if bridge.hasUnigrams(key) {
                if Preferences.selectPhraseAfterCursorAsCandidate {
                    bridge.gridDeleteReadingAfterCursor()
                } else {
                    bridge.gridDeleteReadingBeforeCursor()
                }
                bridge.gridInsertReading(key)
                bridge.walk()
                if inputMode == .plainBopomofo {
                    let candidateState = bridge.buildCandidateStateFromInputtingState(
                        bridge.buildInputtingState(), useVerticalMode: input.useVerticalMode)
                    if candidateState.candidates.count == 1 {
                        clear()
                        stateCallback(
                            InputState.Committing(
                                poppedText: candidateState.candidates.first!.value))
                        stateCallback(InputState.Empty())
                    } else {
                        stateCallback(candidateState)
                    }
                } else {
                    stateCallback(bridge.buildInputtingState())
                }
                return true
            }
        }

        var cancelCandidateKey =
            charCode == 27 || charCode == 8 || input.isDelete

        var isCursorMovingLeft = false
        var isCursorMovingRight = false

        if state is InputState.ChoosingPunctuationList {
            isCursorMovingLeft = false
            isCursorMovingRight = false
        } else if input.isShiftHold {
            isCursorMovingLeft = input.isLeft
            isCursorMovingRight = input.isRight
        } else {
            switch Preferences.allowMovingCursorWhenChoosingCandidates {
            case .useJK:
                isCursorMovingLeft = inputText == "j"
                isCursorMovingRight = inputText == "k"
            case .useHL:
                isCursorMovingLeft = inputText == "h"
                isCursorMovingRight = inputText == "l"
            default:
                break
            }
        }

        if state is InputState.ChoosingCandidate && (isCursorMovingLeft || isCursorMovingRight) {
            if isCursorMovingLeft {
                if bridge.gridCursor > 0 {
                    bridge.gridCursor = bridge.gridCursor - 1
                } else {
                    errorCallback()
                    return true
                }
            } else {
                if bridge.gridCursor < bridge.gridLength {
                    bridge.gridCursor = bridge.gridCursor + 1
                } else {
                    errorCallback()
                    return true
                }
            }
            let choosingState = state as! InputState.ChoosingCandidate
            let newState = bridge.buildCandidateStateFromInputtingState(
                bridge.buildInputtingState(), useVerticalMode: choosingState.useVerticalMode)
            stateCallback(newState)
            return true
        }

        let invalidPrefixArray = [
            "_half_punctuation_", "_ctrl_punctuation_", "_letter_", "_number_", "_punctuation_",
        ]

        // Handle +/- boost/exclude in bopomofo mode
        if inputMode == .bopomofo, state is InputState.ChoosingCandidate {
            let isPlusKey = inputText == "=" || inputText == "+"
            let isMinusKey = inputText == "-" || inputText == "_"
            if isPlusKey || isMinusKey {
                let currentState = state as! InputState.ChoosingCandidate
                let index = Int(gCurrentCandidateController?.selectedCandidateIndex ?? 0)
                let candidate = currentState.candidates[index]
                let reading = candidate.reading

                if candidate.value != candidate.rawValue {
                    return true
                }

                for invalidPrefix in invalidPrefixArray {
                    if reading.hasPrefix(invalidPrefix) {
                        errorCallback()
                        return true
                    }
                }
                if !reading.contains("-") {
                    errorCallback()
                    return true
                }

                var entries: [InputState.CustomMenuEntry] = []
                let title: String
                if isPlusKey {
                    let callback: () -> Void = { [weak self] in
                        guard let self else { return }
                        self.delegate?.keyHandler(
                            self, didRequestBoostScoreForPhrase: candidate.value,
                            reading: reading)
                        self.delegate?.keyHandlerDidRequestReloadLanguageModel(self)
                        self.bridge.walk()
                        stateCallback(self.bridge.buildInputtingState())
                    }
                    entries.append(
                        InputState.CustomMenuEntry(
                            title: NSLocalizedString("Boost", comment: ""), callback: callback))
                    title = String(
                        format: NSLocalizedString(
                            "Do you want to boost the score of the phrase \"%@\"?", comment: ""),
                        candidate.value)
                } else {
                    let callback: () -> Void = { [weak self] in
                        guard let self else { return }
                        self.delegate?.keyHandler(
                            self, didRequestExcludePhrase: candidate.value, reading: reading)
                        self.delegate?.keyHandlerDidRequestReloadLanguageModel(self)
                        self.bridge.walk()
                        stateCallback(self.bridge.buildInputtingState())
                    }
                    entries.append(
                        InputState.CustomMenuEntry(
                            title: NSLocalizedString("Exclude", comment: ""), callback: callback))
                    title = String(
                        format: NSLocalizedString(
                            "Do you want to exclude the phrase \"%@\"?", comment: ""),
                        candidate.value)
                }
                let cancelCallback: () -> Void = {
                    stateCallback(currentState)
                    gCurrentCandidateController?.selectedCandidateIndex = UInt(index)
                }
                entries.append(
                    InputState.CustomMenuEntry(
                        title: NSLocalizedString("Cancel", comment: ""), callback: cancelCallback))

                let confirm = InputState.CustomMenu(
                    composingBuffer: currentState.composingBuffer,
                    cursorIndex: currentState.cursorIndex, title: title, entries: entries,
                    previousState: currentState, selectedIndex: index)
                stateCallback(confirm)
                return true
            }
        }

        // Handle "?" question mark
        if inputMode == .bopomofo && inputText == "?" {
            if state is InputState.ShowingCharInfo || state is InputState.SelectingDictionary {
                cancelCandidateKey = true
            } else if let choosingState = state as? InputState.ChoosingCandidate {
                let index = Int(gCurrentCandidateController?.selectedCandidateIndex ?? 0)
                let candidate = choosingState.candidates[index]
                let reading = candidate.reading
                for invalidPrefix in invalidPrefixArray {
                    if reading.hasPrefix(invalidPrefix) {
                        errorCallback()
                        return true
                    }
                }
                let newState = InputState.SelectingDictionary(
                    previousState: choosingState, selectedString: candidate.displayText,
                    selectedIndex: index)
                stateCallback(newState)
                return true
            } else if let assocState = state as? InputState.AssociatedPhrases {
                if assocState.autoTriggered {
                    return false
                }
            }
        }

        if cancelCandidateKey {
            if let current = state as? InputState.ShowingCharInfo {
                let selectedIndex = current.previousState.selectedIndex
                stateCallback(current.previousState.previousState)
                let controller = delegate?.candidateController(for: self) as? VTCandidateController
                controller?.selectedCandidateIndex = UInt(selectedIndex)
            } else if let current = state as? InputState.SelectingDictionary {
                let selectedIndex = current.selectedIndex
                stateCallback(current.previousState)
                let controller = delegate?.candidateController(for: self) as? VTCandidateController
                controller?.selectedCandidateIndex = UInt(selectedIndex)
            } else if let current = state as? InputState.CustomMenu {
                let selectedIndex = current.selectedIndex
                stateCallback(current.previousState)
                let controller = delegate?.candidateController(for: self) as? VTCandidateController
                controller?.selectedCandidateIndex = UInt(selectedIndex)
            } else if state is InputState.SelectingFeature {
                clear()
                stateCallback(InputState.EmptyIgnoringPreviousState())
            } else if let assocState = state as? InputState.AssociatedPhrases {
                if assocState.autoTriggered {
                    return false
                }
                let selectedIndex = assocState.selectedIndex
                stateCallback(assocState.previousState)
                let controller = delegate?.candidateController(for: self) as? VTCandidateController
                controller?.selectedCandidateIndex = UInt(selectedIndex)
            } else if state is InputState.AssociatedPhrasesPlain {
                clear()
                stateCallback(InputState.EmptyIgnoringPreviousState())
            } else if state is InputState.IrohaKanaCandidates {
                clear()
                stateCallback(InputState.EmptyIgnoringPreviousState())
            } else if inputMode == .plainBopomofo {
                clear()
                stateCallback(InputState.EmptyIgnoringPreviousState())
            } else if state is InputState.ChoosingPunctuationList {
                if Preferences.selectPhraseAfterCursorAsCandidate {
                    bridge.gridDeleteReadingAfterCursor()
                } else {
                    bridge.gridDeleteReadingBeforeCursor()
                }
                if bridge.gridLength == 0 {
                    clear()
                    stateCallback(InputState.EmptyIgnoringPreviousState())
                } else {
                    bridge.walk()
                    stateCallback(bridge.buildInputtingState())
                }
            } else if let choosingState = state as? InputState.ChoosingCandidate {
                bridge.gridCursor = choosingState.originalCursorIndex
                stateCallback(bridge.buildInputtingState())
            } else {
                stateCallback(bridge.buildInputtingState())
            }
            return true
        }

        if charCode == 13 || input.isEnter {
            if let numberState = state as? InputState.Number {
                let candidate = numberState.candidates[Int(gCurrentCandidateController?.selectedCandidateIndex ?? 0)]
                stateCallback(InputState.Committing(poppedText: candidate))
                stateCallback(InputState.Empty())
                return true
            }

            if Preferences.shiftEnterEnabled && inputMode == .bopomofo && input.isShiftHold,
                let choosingState = state as? InputState.ChoosingCandidate
            {
                let selectedIdx = Int(gCurrentCandidateController?.selectedCandidateIndex ?? 0)
                let candidate = choosingState.candidates[selectedIdx]
                let params = BuildAssociatedPhraseParams()
                params.previousState = choosingState
                params.prefixCursorIndex = NSUInteger(computeActualCursorIndex(Int(choosingState.originalCursorIndex)))
                params.reading = candidate.reading
                params.value = candidate.value
                params.candidateIndex = 0
                params.useVerticalMode = choosingState.useVerticalMode
                params.autoTriggered = false
                if let newState = bridge.buildAssociatedPhraseStateWithParams(params) {
                    stateCallback(newState)
                } else {
                    errorCallback()
                }
                return true
            }

            if state is InputState.AssociatedPhrasesPlain {
                clear()
                stateCallback(InputState.EmptyIgnoringPreviousState())
                return true
            }

            let idx = Int(gCurrentCandidateController?.selectedCandidateIndex ?? 0)
            delegate?.keyHandler(
                self, didSelectCandidateAt: idx,
                candidateController: gCurrentCandidateController as Any)
            return true
        }

        // Handle space key for associated phrases
        if charCode == 32, let assocState = state as? InputState.AssociatedPhrases,
            assocState.autoTriggered
        {
            return false
        }

        var isPageDown =
            charCode == 32 || input.isPageDown || input.emacsKey == .nextPage
        var isPageUp = input.isPageUp
        switch Preferences.allowMovingCursorWhenChoosingCandidates {
        case .useJK:
            isPageDown = isPageDown || inputText == "l"
            isPageUp = isPageUp || inputText == "h"
        case .useHL:
            isPageDown = isPageDown || inputText == "k"
            isPageUp = isPageUp || inputText == "j"
        default:
            break
        }

        if isPageDown {
            if let assocState = state as? InputState.AssociatedPhrases, assocState.autoTriggered {
                return false
            }
            let updated = gCurrentCandidateController?.showNextPage() ?? false
            if !updated {
                errorCallback()
            }
            return true
        }

        if isPageUp {
            if let assocState = state as? InputState.AssociatedPhrases, assocState.autoTriggered {
                return false
            }
            let updated = gCurrentCandidateController?.showPreviousPage() ?? false
            if !updated {
                errorCallback()
            }
            return true
        }

        var candidateCount: Int = 0
        if let provider = state as? CandidateProvider {
            candidateCount = provider.candidateCount
        }

        if input.isLeft {
            if let assocState = state as? InputState.AssociatedPhrases, assocState.autoTriggered {
                if let ctrl = gCurrentCandidateController,
                    ctrl is VTHorizontalCandidateController
                {
                    if ctrl.selectedCandidateIndex == 0 {
                        return false
                    }
                } else {
                    return false
                }
                if input.isShiftHold {
                    return false
                }
            }

            if gCurrentCandidateController is VTHorizontalCandidateController {
                let updated = gCurrentCandidateController?.highlightPreviousCandidate() ?? false
                if !updated {
                    errorCallback()
                }
            } else {
                let updated = gCurrentCandidateController?.showPreviousPage() ?? false
                if !updated {
                    errorCallback()
                }
            }
            return true
        }

        if input.emacsKey == .backward {
            let updated = gCurrentCandidateController?.highlightPreviousCandidate() ?? false
            if !updated {
                errorCallback()
            }
            return true
        }

        if input.isRight {
            if let assocState = state as? InputState.AssociatedPhrases, assocState.autoTriggered {
                if let ctrl = gCurrentCandidateController,
                    ctrl is VTHorizontalCandidateController
                {
                    if ctrl.selectedCandidateIndex == UInt(candidateCount) - 1 {
                        return false
                    }
                } else {
                    return false
                }
                if input.isShiftHold {
                    return false
                }
            }

            if gCurrentCandidateController is VTHorizontalCandidateController {
                let updated = gCurrentCandidateController?.highlightNextCandidate() ?? false
                if !updated {
                    errorCallback()
                }
            } else {
                let updated = gCurrentCandidateController?.showNextPage() ?? false
                if !updated {
                    errorCallback()
                }
            }
            return true
        }

        if input.emacsKey == .forward {
            let updated = gCurrentCandidateController?.highlightNextCandidate() ?? false
            if !updated {
                errorCallback()
            }
            return true
        }

        if input.isUp {
            if gCurrentCandidateController is VTHorizontalCandidateController {
                let updated = gCurrentCandidateController?.showPreviousPage() ?? false
                if !updated {
                    errorCallback()
                }
            } else {
                let updated = gCurrentCandidateController?.highlightPreviousCandidate() ?? false
                if !updated {
                    errorCallback()
                }
            }
            return true
        }

        if input.isDown {
            if gCurrentCandidateController is VTHorizontalCandidateController {
                let updated = gCurrentCandidateController?.showNextPage() ?? false
                if !updated {
                    errorCallback()
                }
            } else {
                let updated = gCurrentCandidateController?.highlightNextCandidate() ?? false
                if !updated {
                    errorCallback()
                }
            }
            return true
        }

        if input.isHome || input.emacsKey == .home {
            if gCurrentCandidateController?.selectedCandidateIndex == 0 {
                errorCallback()
            } else {
                gCurrentCandidateController?.selectedCandidateIndex = 0
            }
            return true
        }

        if candidateCount == 0 {
            return false
        }

        if (input.isEnd || input.emacsKey == .end) && candidateCount > 0 {
            if gCurrentCandidateController?.selectedCandidateIndex == UInt(candidateCount) - 1 {
                errorCallback()
            } else {
                gCurrentCandidateController?.selectedCandidateIndex = UInt(candidateCount) - 1
            }
            return true
        }

        var useInputTextIgnoringModifiers = false
        if state is InputState.AssociatedPhrasesPlain || state is InputState.Number {
            useInputTextIgnoringModifiers = true
        } else if let assocState = state as? InputState.AssociatedPhrases {
            useInputTextIgnoringModifiers = assocState.autoTriggered
        }

        if useInputTextIgnoringModifiers {
            if !input.isShiftHold {
                return false
            }
        }

        let match: String
        if useInputTextIgnoringModifiers {
            match = input.inputTextIgnoringModifiers
        } else {
            match = inputText
        }

        var foundIndex = -1
        for (j, label) in (gCurrentCandidateController?.keyLabels ?? []).enumerated() {
            if match.compare(label.key, options: .caseInsensitive) == .orderedSame {
                foundIndex = j
                break
            }
        }

        if foundIndex >= 0 {
            let candidateIndex =
                gCurrentCandidateController?.candidateIndex(atKeyLabelIndex: UInt(foundIndex))
                ?? UInt.max
            if candidateIndex != UInt.max {
                delegate?.keyHandler(
                    self, didSelectCandidateAt: Int(candidateIndex),
                    candidateController: gCurrentCandidateController as Any)
                return true
            }
        }

        if useInputTextIgnoringModifiers {
            return false
        }

        // Plain bopomofo auto-select
        if inputMode == .plainBopomofo {
            let shouldAutoSelect = bridge.shouldAutoSelectCandidate(
                forCharCode: charCode, controlHold: input.isControlHold,
                halfWidthPunctuationEnabled: Preferences.halfWidthPunctuationEnabled)

            if shouldAutoSelect {
                let candidateIndex =
                    gCurrentCandidateController?.candidateIndex(atKeyLabelIndex: 0) ?? UInt.max
                if candidateIndex != UInt.max {
                    delegate?.keyHandler(
                        self, didSelectCandidateAt: Int(candidateIndex),
                        candidateController: gCurrentCandidateController as Any)
                    clear()
                    let empty = InputState.EmptyIgnoringPreviousState()
                    stateCallback(empty)
                    handle(
                        input: input, state: empty, stateCallback: stateCallback,
                        errorCallback: errorCallback)
                }
                return true
            }
        }

        errorCallback()
        return true
    }

    private func candidatesForNumberString(_ number: String) -> [String] {
        if number.isEmpty {
            return []
        }
        var array: [String] = []
        let composedCandidateArray = NumberInputHelper.candidate(forNumberString: number)
        array.append(contentsOf: composedCandidateArray)
        let key = "_number_" + number
        if bridge.hasUnigrams(key) {
            for candidate in bridge.unigramsForKey(key) {
                if !array.contains(candidate) {
                    array.append(candidate)
                }
            }
        }
        let components = NumberInputHelper.split(withNumberString: number)
        let intPart = components[0]
        let decPart = components[1]
        let suzhouNumber = SuzhouNumbers.generate(
            withIntPart: intPart, decPart: decPart, unit: "[單位]", preferInitialVertical: true)
        array.append(suzhouNumber)
        return array
    }

    @discardableResult
    private func handleNumberState(
        state: InputState, input: KeyHandlerInput,
        stateCallback: (InputState) -> Void, errorCallback: () -> Void
    ) -> Bool {
        let numberState = state as! InputState.Number
        let charCode = input.charCode
        if charCode == 27 {
            stateCallback(InputState.Empty())
            return true
        }
        if charCode == 8 || input.isDelete {
            var number = numberState.number
            if !number.isEmpty {
                number = String(number.dropLast())
            } else {
                errorCallback()
                return true
            }
            let candidates = candidatesForNumberString(number)
            stateCallback(InputState.Number(number: number, candidates: candidates))
            return true
        }
        if charCode >= UInt16(("0" as UnicodeScalar).value)
            && charCode <= UInt16(("9" as UnicodeScalar).value)
        {
            if numberState.number.count > 20 {
                errorCallback()
                return true
            }
            let appended = numberState.number + String(format: "%c", charCode)
            let candidates = candidatesForNumberString(appended)
            stateCallback(InputState.Number(number: appended, candidates: candidates))
            return true
        } else if charCode == UInt16(("." as UnicodeScalar).value) {
            if numberState.number.contains(".") {
                errorCallback()
                return true
            }
            if numberState.number.isEmpty || numberState.number.count > 20 {
                errorCallback()
                return true
            }
            let appended = numberState.number + "."
            let candidates = candidatesForNumberString(appended)
            stateCallback(InputState.Number(number: appended, candidates: candidates))
            return true
        }
        return false
    }

    @discardableResult
    private func handleBig5State(
        state: InputState, input: KeyHandlerInput,
        stateCallback: (InputState) -> Void, errorCallback: () -> Void
    ) -> Bool {
        let big5State = state as! InputState.Big5
        let charCode = input.charCode
        if charCode == 27 {
            stateCallback(InputState.Empty())
            return true
        }
        if charCode == 8 || input.isDelete {
            var code = big5State.code
            if !code.isEmpty {
                code = String(code.dropLast())
            }
            stateCallback(InputState.Big5(code: code))
            return true
        }
        if (charCode >= UInt16(("0" as UnicodeScalar).value) && charCode <= UInt16(("9" as UnicodeScalar).value))
            || (charCode >= UInt16(("a" as UnicodeScalar).value) && charCode <= UInt16(("f" as UnicodeScalar).value))
        {
            let appended = big5State.code + String(format: "%c", toupper(Int32(charCode)))
            if appended.count == 4 {
                let big5Code = strtol(appended, nil, 16)
                var bytes = [Int8](repeating: 0, count: 3)
                bytes[0] = Int8(bitPattern: UInt8((big5Code >> 8) & 0xff))
                bytes[1] = Int8(bitPattern: UInt8(big5Code & 0xff))
                let cfString = CFStringCreateWithCString(
                    nil, &bytes, CFStringBuiltInEncodings.Big5_HKSCS_1999.rawValue)
                if cfString == nil {
                    errorCallback()
                    stateCallback(InputState.Empty())
                    return true
                }
                let string = cfString! as String
                stateCallback(InputState.Committing(poppedText: string))
                stateCallback(InputState.Empty())
            } else {
                stateCallback(InputState.Big5(code: appended))
            }
            return true
        }
        errorCallback()
        return true
    }

    @discardableResult
    private func handleIrohaKanaState(
        state: InputState, input: KeyHandlerInput,
        stateCallback: (InputState) -> Void, errorCallback: () -> Void
    ) -> Bool {
        let irohaKana = state as! InputState.IrohaKana
        let charCode = input.charCode
        if charCode == 27 {
            stateCallback(InputState.Empty())
            return true
        }
        if charCode == 13 || charCode == 32 {
            let code = irohaKana.code
            if code.isEmpty {
                stateCallback(InputState.Empty())
                return true
            }
            let key = "_kana_" + code
            if bridge.hasUnigrams(key) {
                let unigrams = bridge.unigramsForKey(key)
                if unigrams.count == 1 {
                    stateCallback(InputState.Committing(poppedText: unigrams[0]))
                    stateCallback(InputState.IrohaKana(code: ""))
                } else {
                    stateCallback(InputState.IrohaKanaCandidates(code: code, candidates: unigrams))
                }
                return true
            }
            errorCallback()
            stateCallback(InputState.IrohaKana(code: ""))
            return true
        }
        if charCode == 8 || input.isDelete {
            let code = irohaKana.code
            if code.isEmpty {
                stateCallback(InputState.IrohaKana(code: ""))
                return true
            }
            stateCallback(InputState.IrohaKana(code: String(code.dropLast())))
            return true
        }
        if (charCode >= UInt16(("a" as UnicodeScalar).value) && charCode <= UInt16(("z" as UnicodeScalar).value))
            || (charCode >= UInt16(("A" as UnicodeScalar).value) && charCode <= UInt16(("Z" as UnicodeScalar).value))
        {
            if irohaKana.code.count >= 4 {
                errorCallback()
                return true
            }
            let appended = irohaKana.code + String(format: "%c", tolower(Int32(charCode)))
            stateCallback(InputState.IrohaKana(code: appended))
            return true
        }
        errorCallback()
        return true
    }

    private func inputtingStateWithMarkingStateUnsupportedTooltip(state: InputState.Inputting)
        -> InputState.Inputting
    {
        let updatedState = InputState.Inputting(
            composingBuffer: state.composingBuffer, cursorIndex: state.cursorIndex)
        updatedState.tooltip = NSLocalizedString(
            "Cannot add new phrases when Bopomofo annotation is on", comment: "")
        return updatedState
    }
}
