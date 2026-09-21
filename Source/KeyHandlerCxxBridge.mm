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

#import "KeyHandlerCxxBridge.h"
#import "LanguageModelManagerBridge+Privates.h"
#import "Mandarin.h"
#import "McBopomofo-Swift.h"
#import "McBopomofoLM.h"
#import "UTF8Helper.h"
#import "UserOverrideModel.h"
#import "reading_grid.h"

#import <algorithm>
#import <optional>
#import <sstream>
#import <string>
#import <unordered_map>
#import <utility>
#import <vector>

@import CandidateUI;
@import NSStringUtils;
@import OpenCCBridge;
@import ChineseNumbers;
@import RomanNumbers;
@import BopomofoBraille;

@implementation KeyHandlerCxxBridge {
    std::shared_ptr<Formosa::Gramambular2::LanguageModel> _emptySharedPtr;

    // the reading buffer that takes user input
    Formosa::Mandarin::BopomofoReadingBuffer *_bpmfReadingBuffer;

    // language model
    McBopomofo::McBopomofoLM *_languageModel;

    // user override model
    McBopomofo::UserOverrideModel *_userOverrideModel;

    Formosa::Gramambular2::ReadingGrid *_grid;
    Formosa::Gramambular2::ReadingGrid::WalkResult _latestWalk;

    NSString *_inputMode;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _bpmfReadingBuffer = new Formosa::Mandarin::BopomofoReadingBuffer(Formosa::Mandarin::BopomofoKeyboardLayout::StandardLayout());

        _languageModel = [LanguageModelManagerBridge languageModelMcBopomofo];
        _languageModel->setPhraseReplacementEnabled(Preferences.phraseReplacementEnabled);
        _userOverrideModel = [LanguageModelManagerBridge userOverrideModel];

        std::shared_ptr<Formosa::Gramambular2::LanguageModel> lm(_emptySharedPtr, _languageModel);
        _grid = new Formosa::Gramambular2::ReadingGrid(lm);
        _grid->setReadingSeparator("-");

        _inputMode = InputModeBopomofo;
    }
    return self;
}

- (void)dealloc
{
    delete _bpmfReadingBuffer;
    delete _grid;
}

- (NSString *)inputMode
{
    return _inputMode;
}

- (void)setInputMode:(NSString *)value
{
    NSString *newInputMode;
    McBopomofo::McBopomofoLM *newLanguageModel;

    if ([value isKindOfClass:[NSString class]] && [value isEqual:InputModePlainBopomofo]) {
        newInputMode = InputModePlainBopomofo;
        newLanguageModel = [LanguageModelManagerBridge languageModelPlainBopomofo];
        newLanguageModel->setPhraseReplacementEnabled(false);
    } else {
        newInputMode = InputModeBopomofo;
        newLanguageModel = [LanguageModelManagerBridge languageModelMcBopomofo];
        newLanguageModel->setPhraseReplacementEnabled(Preferences.phraseReplacementEnabled);
    }
    newLanguageModel->setExternalConverterEnabled(Preferences.chineseConversionStyle == ChineseConversionStyleModel);

    if (![_inputMode isEqualToString:newInputMode]) {
        _inputMode = newInputMode;
        _languageModel = newLanguageModel;

        if (_grid == nullptr) {
            NSLog(@"warning: _grid used after release");
        }

        if (_grid != nullptr) {
            delete _grid;
            std::shared_ptr<Formosa::Gramambular2::LanguageModel> lm(_emptySharedPtr, _languageModel);
            _grid = new Formosa::Gramambular2::ReadingGrid(lm);
            _grid->setReadingSeparator("-");
        }

        if (!_bpmfReadingBuffer->isEmpty()) {
            _bpmfReadingBuffer->clear();
        }
    }
}

- (void)syncWithPreferences
{
    KeyboardLayout layout = Preferences.keyboardLayout;
    switch (layout) {
    case KeyboardLayoutStandard:
        _bpmfReadingBuffer->setKeyboardLayout(Formosa::Mandarin::BopomofoKeyboardLayout::StandardLayout());
        break;
    case KeyboardLayoutEten:
        _bpmfReadingBuffer->setKeyboardLayout(Formosa::Mandarin::BopomofoKeyboardLayout::ETenLayout());
        break;
    case KeyboardLayoutHsu:
        _bpmfReadingBuffer->setKeyboardLayout(Formosa::Mandarin::BopomofoKeyboardLayout::HsuLayout());
        break;
    case KeyboardLayoutEten26:
        _bpmfReadingBuffer->setKeyboardLayout(Formosa::Mandarin::BopomofoKeyboardLayout::ETen26Layout());
        break;
    case KeyboardLayoutHanyuPinyin:
        _bpmfReadingBuffer->setKeyboardLayout(Formosa::Mandarin::BopomofoKeyboardLayout::HanyuPinyinLayout());
        break;
    case KeyboardLayoutIBM:
        _bpmfReadingBuffer->setKeyboardLayout(Formosa::Mandarin::BopomofoKeyboardLayout::IBMLayout());
        break;
    default:
        _bpmfReadingBuffer->setKeyboardLayout(Formosa::Mandarin::BopomofoKeyboardLayout::StandardLayout());
        Preferences.keyboardLayout = KeyboardLayoutStandard;
    }
    _languageModel->setExternalConverterEnabled(Preferences.chineseConversionStyle == ChineseConversionStyleModel);
}

- (void)clear
{
    _bpmfReadingBuffer->clear();
    _grid->clear();
    _latestWalk = Formosa::Gramambular2::ReadingGrid::WalkResult {};
}

// MARK: - BPMF reading buffer

- (BOOL)bpmfReadingBufferIsEmpty
{
    return _bpmfReadingBuffer->isEmpty();
}

- (BOOL)bpmfReadingBufferHasToneMarker
{
    return _bpmfReadingBuffer->hasToneMarker();
}

- (BOOL)bpmfReadingBufferHasToneMarkerOnly
{
    return _bpmfReadingBuffer->hasToneMarkerOnly();
}

- (BOOL)bpmfReadingBufferIsValidKey:(UniChar)charCode
{
    return _bpmfReadingBuffer->isValidKey((char)charCode);
}

- (void)bpmfReadingBufferCombineKey:(UniChar)charCode
{
    _bpmfReadingBuffer->combineKey((char)charCode);
}

- (void)bpmfReadingBufferClear
{
    _bpmfReadingBuffer->clear();
}

- (void)bpmfReadingBufferBackspace
{
    _bpmfReadingBuffer->backspace();
}

- (NSString *)bpmfComposedReading
{
    return @(_bpmfReadingBuffer->syllable().composedString().c_str());
}

// MARK: - Grid

- (NSInteger)gridCursor
{
    return _grid->cursor();
}

- (void)setGridCursor:(NSInteger)cursor
{
    _grid->setCursor((size_t)cursor);
}

- (NSInteger)gridLength
{
    return _grid->length();
}

- (void)gridInsertReading:(NSString *)reading
{
    _grid->insertReading(reading.UTF8String);
}

- (void)gridDeleteReadingBeforeCursor
{
    _grid->deleteReadingBeforeCursor();
}

- (void)gridDeleteReadingAfterCursor
{
    _grid->deleteReadingAfterCursor();
}

- (void)gridClear
{
    _grid->clear();
}

- (NSArray<NSString *> *)gridReadings
{
    NSMutableArray *array = [[NSMutableArray alloc] init];
    for (const auto& reading : _grid->readings()) {
        [array addObject:@(reading.c_str())];
    }
    return array;
}

// MARK: - Walk and language model

- (void)walk
{
    _latestWalk = _grid->walk();
}

- (BOOL)hasUnigrams:(NSString *)key
{
    return _languageModel->hasUnigrams(key.UTF8String);
}

- (NSArray<NSString *> *)unigramsForKey:(NSString *)key
{
    auto unigrams = _languageModel->getUnigrams(key.UTF8String);
    NSMutableArray *array = [[NSMutableArray alloc] init];
    for (const auto& unigram : unigrams) {
        [array addObject:@(unigram.value().c_str())];
    }
    return array;
}

- (void)applyUserOverrideModelAfterWalk
{
    McBopomofo::UserOverrideModel::Suggestion suggestion = _userOverrideModel->suggest(_latestWalk, self.actualCandidateCursorIndex, [NSDate date].timeIntervalSince1970);
    if (!suggestion.empty()) {
        Formosa::Gramambular2::ReadingGrid::Node::OverrideType type = suggestion.forceHighScoreOverride
            ? Formosa::Gramambular2::ReadingGrid::Node::OverrideType::kOverrideValueWithHighScore
            : Formosa::Gramambular2::ReadingGrid::Node::OverrideType::kOverrideValueWithScoreFromTopUnigram;
        _grid->overrideCandidate(self.actualCandidateCursorIndex, suggestion.candidate, type);
        _latestWalk = _grid->walk();
    }
}

// MARK: - State builders

- (InputStateInputting *)buildInputtingState
{
    size_t runningCursor = 0;

    std::string composed;
    size_t builderCursor = _grid->cursor();
    size_t composedCursor = 0;
    NSString *tooltip = @"";

    bool bopomofoAnnotationUsed = false;
    bool bopomofoAnnotationHasPUAs = false;
    bool bopomofoAnnotationHasVariants = false;

    for (const auto& node : _latestWalk.nodes) {
        std::string value = node->value();
        size_t composedValueLength = value.length();

        bool nodeHasBopomofoAnnotation = false;
        McBopomofo::VariantAnnotator::CombinedResult nodeAnnotationResult;
        if (!Preferences.bopomofoFontAnnotationSupportEnabled || _inputMode == InputModePlainBopomofo) {
            composed += value;
        } else if (!LanguageModelManagerBridge.variantAnnotator->loaded()) {
            composed += value;
        } else {
            size_t cpLen = McBopomofo::CodePointCount(value);
            if (cpLen != node->spanningLength()) {
                composed += value;
            } else {
                std::vector<std::string> characters = McBopomofo::Split(value);
                std::vector<std::string> readings = McBopomofo::AssociatedPhrasesV2::SplitReadings(node->reading());
                if (readings.size() != cpLen) {
                    composed += value;
                } else {
                    nodeAnnotationResult = LanguageModelManagerBridge.variantAnnotator->annotate(characters, readings);
                    nodeHasBopomofoAnnotation = true;
                    bopomofoAnnotationUsed = true;
                    bopomofoAnnotationHasPUAs |= nodeAnnotationResult.hasPUACodePoints;
                    bopomofoAnnotationHasVariants |= nodeAnnotationResult.hasVariantSelectors;
                    composed += nodeAnnotationResult.annotatedString;
                    composedValueLength = nodeAnnotationResult.annotatedString.length();
                }
            }
        }

        if (runningCursor == builderCursor) {
            continue;
        }
        size_t readingLength = node->spanningLength();

        if (runningCursor + readingLength <= builderCursor) {
            composedCursor += composedValueLength;
            runningCursor += readingLength;
            continue;
        }

        size_t distance = builderCursor - runningCursor;
        size_t valueCodePointCount = McBopomofo::CodePointCount(value);
        size_t cpLen = std::min(distance, valueCodePointCount);
        std::string actualValue = McBopomofo::SubstringToCodePoints(value, cpLen);

        if (nodeHasBopomofoAnnotation) {
            composedCursor += nodeAnnotationResult.accumulatedStringLength[cpLen];
        } else {
            composedCursor += actualValue.length();
        }
        runningCursor += distance;

        if (valueCodePointCount != readingLength) {
            const std::string& prevReading = _grid->readings()[builderCursor - 1];
            const std::string& nextReading = _grid->readings()[builderCursor];

            tooltip = [NSString stringWithFormat:NSLocalizedString(@"Cursor is between \"%@\" and \"%@\".", @""),
                @(prevReading.c_str()),
                @(nextReading.c_str())];
        }
    }

    if (bopomofoAnnotationUsed) {
        NSString *annotationTooltip = NSLocalizedString(@"Bopomofo annotation support on", @"");
        if (bopomofoAnnotationHasVariants && bopomofoAnnotationHasPUAs) {
            annotationTooltip = NSLocalizedString(@"Bopomofo annotation: variant selectors and PUA blocks in text", @"");
        } else if (bopomofoAnnotationHasVariants) {
            annotationTooltip = NSLocalizedString(@"Bopomofo annotation: variant selectors in text", @"");
        } else if (bopomofoAnnotationHasPUAs) {
            annotationTooltip = NSLocalizedString(@"Bopomofo annotation: PUA blocks in text", @"");
        }

        if ([tooltip length] > 0) {
            tooltip = [NSString stringWithFormat:@"%@ / %@", tooltip, annotationTooltip];
        } else {
            tooltip = annotationTooltip;
        }
    }

    std::string headStr = composed.substr(0, composedCursor);
    std::string tailStr = composed.substr(composedCursor, composed.length() - composedCursor);

    NSString *head = @(headStr.c_str());
    NSString *reading = @(_bpmfReadingBuffer->composedString().c_str());
    NSString *tail = @(tailStr.c_str());
    NSString *composedText = [head stringByAppendingString:[reading stringByAppendingString:tail]];
    NSInteger cursorIndex = head.length + reading.length;
    InputStateInputting *newState = [[InputStateInputting alloc] initWithComposingBuffer:composedText cursorIndex:cursorIndex];
    newState.tooltip = tooltip;
    return newState;
}

- (InputStateChoosingCandidate *)buildCandidateStateFromInputtingState:(InputStateInputting *)inputting useVerticalMode:(BOOL)useVerticalMode
{
    auto candidates = _grid->candidatesAt(self.actualCandidateCursorIndex);

    std::unordered_map<std::string, size_t> valueCountMap;
    for (const auto& c : candidates) {
        ++valueCountMap[c.value];
    }

    NSMutableArray *candidatesArray = [[NSMutableArray alloc] init];
    for (const auto& c : candidates) {
        std::string displayText = c.value;
        if (valueCountMap[displayText] > 1) {
            displayText += " (";
            std::string reading = c.reading;
            std::replace(reading.begin(), reading.end(), '-', ' ');
            displayText += reading;
            displayText += ")";
        }

        NSString *r = @(c.reading.c_str());
        NSString *v = @(c.value.c_str());
        NSString *rv = @(c.rawValue.c_str());
        NSString *dt = @(displayText.c_str());

        InputStateCandidate *candidate = [[InputStateCandidate alloc] initWithReading:r value:v displayText:dt rawValue:rv];
        [candidatesArray addObject:candidate];
    }

    InputStateChoosingCandidate *state = [[InputStateChoosingCandidate alloc] initWithComposingBuffer:inputting.composingBuffer cursorIndex:inputting.cursorIndex candidates:candidatesArray useVerticalMode:useVerticalMode];
    return state;
}

- (nullable InputState *)buildAssociatedPhrasePlainStateWithReading:(NSString *)reading value:(NSString *)value useVerticalMode:(BOOL)useVerticalMode
{
    NSString *actualValue = value;
    BOOL scToTc = Preferences.chineseConversionEnabled && Preferences.chineseConversionStyle == ChineseConversionStyleModel;
    if (scToTc) {
        actualValue = [[OpenCCBridge sharedInstance] convertToTraditional:value];
    }

    std::string cppValue(actualValue.UTF8String);
    std::vector<std::string> readings = McBopomofo::AssociatedPhrasesV2::SplitReadings(std::string(reading.UTF8String));

    std::vector<McBopomofo::AssociatedPhrasesV2::Phrase> phrases = _languageModel->findAssociatedPhrasesV2(cppValue, readings);
    if (!phrases.empty()) {
        NSMutableArray<InputStateCandidate *> *array = [NSMutableArray array];
        for (const auto& phrase : phrases) {
            std::string valueWithoutPrefix = phrase.value.substr(cppValue.length());

            auto readingIter = phrase.readings.cbegin();
            for (auto ri = readings.cbegin(), re = readings.cend(); ri != re && readingIter != phrase.readings.cend(); ++ri) {
                ++readingIter;
                if (readingIter == phrase.readings.cend()) {
                    continue;
                }
            }
            std::vector<std::string> readingsWithoutPrefix { readingIter, phrase.readings.cend() };
            std::string combinedReading = McBopomofo::AssociatedPhrasesV2::CombineReadings(readingsWithoutPrefix);

            NSString *candidateReading = @(combinedReading.c_str());
            NSString *candidateValue = @(valueWithoutPrefix.c_str());
            InputStateCandidate *candidate = [[InputStateCandidate alloc] initWithReading:candidateReading value:candidateValue displayText:candidateValue rawValue:candidateValue];
            [array addObject:candidate];
        }
        InputStateAssociatedPhrasesPlain *associatedPhrases = [[InputStateAssociatedPhrasesPlain alloc] initWithCandidates:array useVerticalMode:useVerticalMode];
        return associatedPhrases;
    }
    return nil;
}

- (nullable InputState *)buildAssociatedPhraseStateWithParams:(BuildAssociatedPhraseParams *)params
{
    BOOL scToTc = Preferences.chineseConversionEnabled && Preferences.chineseConversionStyle == ChineseConversionStyleModel;

    std::vector<std::string> splitReadings = McBopomofo::AssociatedPhrasesV2::SplitReadings(std::string(params.reading.UTF8String));
    NSString *actualValue = params.value;
    if (scToTc) {
        actualValue = [[OpenCCBridge sharedInstance] convertToTraditional:actualValue];
    }
    std::string prefixValue(actualValue.UTF8String);
    std::vector<McBopomofo::AssociatedPhrasesV2::Phrase> phrases = _languageModel->findAssociatedPhrasesV2(prefixValue, splitReadings);

    if (phrases.empty()) {
        return nil;
    }

    NSMutableArray<InputStateCandidate *> *array = [NSMutableArray array];
    for (const auto& phrase : phrases) {
        std::string combinedReading = McBopomofo::AssociatedPhrasesV2::CombineReadings(phrase.readings);
        NSString *candidateReading = @(combinedReading.c_str());
        NSString *candidateValue = @(phrase.value.c_str());

        std::string valueWithoutPrefix = phrase.value.substr(prefixValue.length());
        NSString *displayText = @(valueWithoutPrefix.c_str());

        if (scToTc) {
            candidateValue = [[OpenCCBridge sharedInstance] convertToSimplified:candidateValue];
            displayText = [[OpenCCBridge sharedInstance] convertToSimplified:displayText];
        }

        InputStateCandidate *candidate = [[InputStateCandidate alloc] initWithReading:candidateReading value:candidateValue displayText:displayText rawValue:candidateValue];
        [array addObject:candidate];
    }
    InputStateAssociatedPhrases *associatedPhrases = [[InputStateAssociatedPhrases alloc] initWithPreviousState:params.previousState prefixCursorIndex:params.prefixCursorIndex prefixReading:params.reading prefixValue:params.value selectedIndex:params.candidateIndex candidates:array useVerticalMode:params.useVerticalMode autoTriggered:params.autoTriggered];
    return associatedPhrases;
}

// MARK: - Complex C++ operations

- (void)fixNodeWithReading:(NSString *)reading value:(NSString *)value originalCursorIndex:(NSUInteger)originalCursorIndex useMoveCursorAfterSelectionSetting:(BOOL)flag
{
    size_t actualCursor = self.actualCandidateCursorIndex;
    Formosa::Gramambular2::ReadingGrid::Candidate candidate(reading.UTF8String, value.UTF8String);
    if (!_grid->overrideCandidate(actualCursor, candidate)) {
        return;
    }

    Formosa::Gramambular2::ReadingGrid::WalkResult prevWalk = _latestWalk;
    _latestWalk = _grid->walk();

    size_t accumulatedCursor = 0;
    auto nodeIter = _latestWalk.findNodeAt(actualCursor, &accumulatedCursor);
    if (nodeIter == _latestWalk.nodes.cend()) {
        return;
    }
    Formosa::Gramambular2::ReadingGrid::NodePtr currentNode = *nodeIter;
    if (currentNode != nullptr && currentNode->currentUnigram().score() > -8) {
        _userOverrideModel->observe(prevWalk, _latestWalk, self.actualCandidateCursorIndex, [NSDate date].timeIntervalSince1970);
    }

    if (currentNode != nullptr && flag && Preferences.moveCursorAfterSelectingCandidate) {
        _grid->setCursor(accumulatedCursor);
    } else {
        _grid->setCursor(originalCursorIndex);
    }
}

- (void)fixNodeForAssociatedPhraseWithPrefixAt:(NSUInteger)prefixCursorIndex prefixReading:(NSString *)pfxReading prefixValue:(NSString *)pfxValue associatedPhraseReading:(NSString *)phraseReading associatedPhraseValue:(NSString *)phraseValue
{
    if (_grid->length() == 0) {
        return;
    }

    size_t actualPrefixCursorIndex = (prefixCursorIndex == _grid->length())
        ? prefixCursorIndex - 1
        : prefixCursorIndex;
    size_t accumulatedCursor = 0;
    auto nodeIter = _latestWalk.findNodeAt(actualPrefixCursorIndex, &accumulatedCursor);

    if (accumulatedCursor < (*nodeIter)->spanningLength()) {
        return;
    }

    std::vector<std::string> originalNodeValues = McBopomofo::Split((*nodeIter)->value());
    if (originalNodeValues.size() == (*nodeIter)->spanningLength()) {
        size_t overrideIndex = accumulatedCursor - (*nodeIter)->spanningLength();
        for (const auto& value : originalNodeValues) {
            _grid->overrideCandidate(overrideIndex, value);
            ++overrideIndex;
        }
    }

    std::string prefixReading(pfxReading.UTF8String);
    std::string prefixValue(pfxValue.UTF8String);

    Formosa::Gramambular2::ReadingGrid::Candidate prefixCandidate { prefixReading, prefixValue };
    if (!_grid->overrideCandidate(actualPrefixCursorIndex, prefixCandidate)) {
        return;
    }
    _latestWalk = _grid->walk();

    nodeIter = _latestWalk.findNodeAt(actualPrefixCursorIndex, &accumulatedCursor);
    _grid->setCursor(accumulatedCursor);

    std::string associatedPhraseReading(phraseReading.UTF8String);
    std::string associatedPhraseValue(phraseValue.UTF8String);
    std::vector<std::string> associatedPhraseValues = McBopomofo::Split(associatedPhraseValue);

    size_t nodeSpanningLength = (*nodeIter)->spanningLength();
    std::vector<std::string> splitReadings = McBopomofo::AssociatedPhrasesV2::SplitReadings(associatedPhraseReading);
    size_t splitReadingsSize = splitReadings.size();
    if (nodeSpanningLength >= splitReadingsSize) {
        return;
    }

    for (size_t i = nodeSpanningLength; i < splitReadingsSize; i++) {
        _grid->insertReading(splitReadings[i]);
        ++accumulatedCursor;
        if (i < associatedPhraseValues.size()) {
            _grid->overrideCandidate(accumulatedCursor, associatedPhraseValues[i]);
        }
        _grid->setCursor(accumulatedCursor);
    }

    if (!_grid->overrideCandidate(actualPrefixCursorIndex, associatedPhraseValue)) {
        // Shouldn't happen
    }

    _latestWalk = _grid->walk();
}

- (BOOL)handleAssociatedPhraseWithState:(InputState *)state useVerticalMode:(BOOL)useVerticalMode stateCallback:(void(^)(InputState*))stateCallback errorCallback:(void(^)(void))errorCallback autoTriggered:(BOOL)autoTriggered maxCandidateCount:(NSUInteger)maxCandidateCount
{
    InputStateInputting *inputtingState = nil;
    if ([state isKindOfClass:[InputStateInputting class]]) {
        inputtingState = (InputStateInputting *)state;
    } else {
        errorCallback();
        return YES;
    }

    size_t cursor = _grid->cursor();

    if (cursor < 1) {
        errorCallback();
        return YES;
    }

    size_t prefixCursorIndex = cursor - 1;

    size_t endCursorIndex = 0;
    auto nodePtrIt = _latestWalk.findNodeAt(prefixCursorIndex, &endCursorIndex);
    if (nodePtrIt == _latestWalk.nodes.cend() || endCursorIndex == 0) {
        errorCallback();
        return YES;
    }

    std::vector<std::string> codepoints = McBopomofo::Split((*nodePtrIt)->value());
    std::vector<std::string> readings = McBopomofo::AssociatedPhrasesV2::SplitReadings((*nodePtrIt)->reading());
    if (codepoints.size() != readings.size()) {
        errorCallback();
        return YES;
    }

    if (endCursorIndex < readings.size()) {
        errorCallback();
        return YES;
    }

    size_t startCursorIndex = endCursorIndex - readings.size();
    size_t prefixLength = cursor - startCursorIndex;
    size_t maxPrefixLength = prefixLength;
    for (; prefixLength > 0; --prefixLength) {
        size_t startIndex = maxPrefixLength - prefixLength;
        auto cpBegin = codepoints.cbegin();
        auto cpEnd = codepoints.cbegin();
        std::advance(cpBegin, startIndex);
        std::advance(cpEnd, maxPrefixLength);
        auto cpSlice = std::vector<std::string>(cpBegin, cpEnd);

        auto rdBegin = readings.cbegin();
        auto rdEnd = readings.cbegin();
        std::advance(rdBegin, startIndex);
        std::advance(rdEnd, maxPrefixLength);
        auto rdSlice = std::vector<std::string>(rdBegin, rdEnd);

        std::stringstream value;
        for (const std::string& cp : cpSlice) {
            value << cp;
        }

        NSString *combinedReading = @(McBopomofo::AssociatedPhrasesV2::CombineReadings(rdSlice).c_str());
        NSString *actualValue = @(value.str().c_str());
        BuildAssociatedPhraseParams *params = [[BuildAssociatedPhraseParams alloc] init];
        params.previousState = inputtingState;
        params.prefixCursorIndex = prefixCursorIndex;
        params.reading = combinedReading;
        params.value = actualValue;
        params.candidateIndex = 0;
        params.useVerticalMode = useVerticalMode;
        params.autoTriggered = autoTriggered;
        InputState *newState = [self buildAssociatedPhraseStateWithParams:params];
        if (newState) {
            stateCallback(newState);
            return YES;
        }
    }
    if (!autoTriggered) {
        errorCallback();
    }
    return YES;
}

- (BOOL)handleTabWithState:(InputState *)state shiftIsHold:(BOOL)shiftIsHold stateCallback:(void(^)(InputState*))stateCallback errorCallback:(void(^)(void))errorCallback
{
    if (!_grid->length()) {
        return NO;
    }

    if (!_bpmfReadingBuffer->isEmpty()) {
        return NO;
    }

    if (![state isKindOfClass:[InputStateInputting class]]) {
        return NO;
    }

    size_t endCursorIndex = 0;
    size_t actualCandidateCursorIndex = self.actualCandidateCursorIndex;
    auto nodeIter = _latestWalk.findNodeAt(actualCandidateCursorIndex, &endCursorIndex);
    if (nodeIter == _latestWalk.nodes.cend()) {
        errorCallback();
        return YES;
    }

    NSString *currentReading = @((*nodeIter)->reading().c_str());
    auto candidates = _grid->candidatesAt(actualCandidateCursorIndex);
    size_t candidateCount = candidates.size();
    if (candidateCount <= 1) {
        errorCallback();
        return YES;
    }

    std::string currentValue = (*nodeIter)->currentUnigram().value();
    size_t currentIndex = 0;
    for (size_t i = 0; i < candidateCount; ++i) {
        if (candidates[i].value == currentValue) {
            currentIndex = i;
            break;
        }
    }

    size_t nextIndex = shiftIsHold
        ? (currentIndex == 0 ? candidateCount - 1 : currentIndex - 1)
        : (currentIndex + 1) % candidateCount;

    NSString *nextValue = @(candidates[nextIndex].value.c_str());
    NSString *nextReading = @(candidates[nextIndex].reading.c_str());

    Formosa::Gramambular2::ReadingGrid::Candidate candidate(candidates[nextIndex].reading, candidates[nextIndex].value);
    _grid->overrideCandidate(actualCandidateCursorIndex, candidate);
    _latestWalk = _grid->walk();

    InputStateInputting *inputting = (InputStateInputting *)[self buildInputtingState];
    if (!inputting) {
        errorCallback();
        return YES;
    }

    if (_inputMode == InputModeBopomofo) {
        inputting.tooltip = [NSString stringWithFormat:NSLocalizedString(@"%@ %@", @""), nextReading, nextValue];
    } else {
        inputting.tooltip = nextValue;
    }
    stateCallback(inputting);
    return YES;
}

- (BOOL)handlePunctuation:(NSString *)punc state:(InputState *)state useVerticalMode:(BOOL)useVerticalMode stateCallback:(void(^)(InputState*))stateCallback errorCallback:(void(^)(void))errorCallback
{
    std::string customPunctuation(punc.UTF8String);

    if (!_languageModel->hasUnigrams(customPunctuation)) {
        return NO;
    }

    if (Preferences.repeatedPunctuationToSelectCandidateEnabled) {
        size_t prefixCursorIndex = _grid->cursor();
        size_t actualPrefixCursorIndex = prefixCursorIndex > 0 ? prefixCursorIndex - 1 : 0;
        size_t accumulatedCursor = 0;
        auto nodeIter = _latestWalk.findNodeAt(actualPrefixCursorIndex, &accumulatedCursor);

        if (nodeIter != _latestWalk.nodes.cend()) {
            std::string existingReading = (*nodeIter)->reading();
            if (existingReading == customPunctuation) {
                auto candidates = _grid->candidatesAt(actualPrefixCursorIndex);
                size_t candidateCount = candidates.size();
                std::string currentValue = (*nodeIter)->currentUnigram().value();
                size_t currentIndex = 0;
                for (size_t i = 0; i < candidateCount; ++i) {
                    if (candidates[i].value == currentValue) {
                        currentIndex = i;
                        break;
                    }
                }
                size_t nextIndex = (currentIndex + 1) % candidateCount;
                Formosa::Gramambular2::ReadingGrid::Candidate candidate(candidates[nextIndex].reading, candidates[nextIndex].value);
                _grid->overrideCandidate(actualPrefixCursorIndex, candidate);
                _latestWalk = _grid->walk();

                InputStateInputting *inputting = (InputStateInputting *)[self buildInputtingState];
                stateCallback(inputting);
                return YES;
            }
        }
    }

    if (_bpmfReadingBuffer->isEmpty()) {
        _grid->insertReading(customPunctuation);
        [self walk];

        if (_inputMode == InputModePlainBopomofo) {
            InputStateInputting *inputting = (InputStateInputting *)[self buildInputtingState];
            InputStateChoosingCandidate *choosingCandidates = [self buildCandidateStateFromInputtingState:inputting useVerticalMode:useVerticalMode];

            if (choosingCandidates.candidates.count == 1) {
                [self clear];
                InputStateCommitting *committing = [[InputStateCommitting alloc] initWithPoppedText:choosingCandidates.candidates.firstObject.value];
                stateCallback(committing);
                InputStateEmpty *empty = [[InputStateEmpty alloc] init];
                stateCallback(empty);
            } else {
                stateCallback(choosingCandidates);
            }
        } else {
            InputStateInputting *inputting = (InputStateInputting *)[self buildInputtingState];
            stateCallback(inputting);
        }
    } else {
        errorCallback();
        stateCallback(state);
    }

    return YES;
}

- (BOOL)shouldAutoSelectCandidateForCharCode:(UniChar)charCode controlHold:(BOOL)controlHold halfWidthPunctuationEnabled:(BOOL)halfWidth
{
    std::string layout = [self currentLayout];
    std::string punctuationNamePrefix;
    if (controlHold) {
        punctuationNamePrefix = "_ctrl_punctuation_";
    } else if (halfWidth) {
        punctuationNamePrefix = "_half_punctuation_";
    } else {
        punctuationNamePrefix = "_punctuation_";
    }
    std::string customPunctuation = punctuationNamePrefix + layout + std::string(1, (char)charCode);
    std::string punctuation = punctuationNamePrefix + std::string(1, (char)charCode);

    BOOL shouldAutoSelectCandidate = _bpmfReadingBuffer->isValidKey((char)charCode)
        || _languageModel->hasUnigrams(customPunctuation)
        || _languageModel->hasUnigrams(punctuation);

    if (!shouldAutoSelectCandidate && (char)charCode >= 'A' && (char)charCode <= 'Z') {
        std::string letter = std::string("_letter_") + std::string(1, (char)charCode);
        if (_languageModel->hasUnigrams(letter)) {
            shouldAutoSelectCandidate = YES;
        }
    }
    return shouldAutoSelectCandidate;
}

- (nullable InputStateInputting *)tryChangePriorToneWithCharCode:(UniChar)charCode
{
    if (!(_bpmfReadingBuffer->hasToneMarkerOnly() && _grid->readings().size() > 0 && _grid->cursor() > 0 && Preferences.allowChangingPriorTone)) {
        return nil;
    }

    size_t cursor = _grid->cursor() - 1;
    const std::string& reading = _grid->readings()[cursor];
    if (reading.empty() || reading[0] == '_') {
        return nil;
    }

    Formosa::Mandarin::BopomofoReadingBuffer tmpBuffer(_bpmfReadingBuffer->keyboardLayout());
    Formosa::Mandarin::BopomofoSyllable syllable = Formosa::Mandarin::BopomofoSyllable::FromComposedString(reading);
    std::string keys = _bpmfReadingBuffer->keyboardLayout()->keySequenceFromSyllable(syllable);
    for (char k : keys) {
        tmpBuffer.combineKey(k);
    }
    tmpBuffer.combineKey((char)charCode);
    std::string newReading = tmpBuffer.syllable().composedString();
    if (!_languageModel->hasUnigrams(newReading)) {
        return nil;
    }

    _bpmfReadingBuffer->clear();
    _grid->deleteReadingBeforeCursor();
    _grid->insertReading(newReading);
    _latestWalk = _grid->walk();
    InputStateInputting *inputting = (InputStateInputting *)[self buildInputtingState];
    return inputting;
}

- (NSArray<NSString *> *)collectUserFileIssues
{
    NSMutableArray<NSString *> *array = [NSMutableArray array];

    std::vector<McBopomofo::McBopomofoLM::UserFileIssue> issues = _languageModel->getUserFileIssues();
    for (const auto& issue : issues) {
        NSMutableString *msg = [NSMutableString string];

        switch (issue.fileType) {
        case McBopomofo::McBopomofoLM::UserFileType::USER_PHRASES:
            [msg appendString:NSLocalizedString(@"User phrase file", "")];
            break;
        case McBopomofo::McBopomofoLM::UserFileType::EXCLUDED_PHRASES:
            [msg appendString:NSLocalizedString(@"Excluded phrase file", "")];
            break;
        case McBopomofo::McBopomofoLM::UserFileType::PHRASE_REPLACEMENT_MAP:
            [msg appendString:NSLocalizedString(@"Phrase replacement file", "")];
            break;
        default:
            [msg appendString:@"Unknown user file"];
            break;
        }

        [msg appendFormat:@" (%@) ", [NSString stringWithUTF8String:issue.path.filename().c_str()]];
        [msg appendFormat:NSLocalizedString(@"line %lu: ", ""), issue.lineNumber];

        switch (issue.issueType) {
        case McBopomofo::McBopomofoLM::IssueType::MISSING_SECOND_COLUMN:
            [msg appendString:NSLocalizedString(@"Only one column was found.", "")];
            break;
        case McBopomofo::McBopomofoLM::IssueType::NULL_CHARACTER_IN_TEXT:
            [msg appendString:NSLocalizedString(@"Illegal NULL character was found.", "")];
            break;
        case McBopomofo::McBopomofoLM::IssueType::NO_ISSUE:
        default:
            [msg appendString:@"Unknown issue."];
            break;
        }

        [array addObject:msg];
    }

    return array;
}

// MARK: - Walk node access

- (BOOL)walkNodeIsOverriddenAtActualCandidateCursor
{
    size_t actualCursor = self.actualCandidateCursorIndex;
    size_t endCursorIndex = 0;
    auto nodeIter = _latestWalk.findNodeAt(actualCursor, &endCursorIndex);
    if (nodeIter == _latestWalk.nodes.cend()) {
        return NO;
    }
    return (*nodeIter)->currentUnigram().score() > -8;
}

- (nullable NSString *)walkNodeReadingAtActualCandidateCursor
{
    size_t actualCursor = self.actualCandidateCursorIndex;
    size_t endCursorIndex = 0;
    auto nodeIter = _latestWalk.findNodeAt(actualCursor, &endCursorIndex);
    if (nodeIter == _latestWalk.nodes.cend()) {
        return nil;
    }
    return @((*nodeIter)->reading().c_str());
}

- (nullable NSString *)walkNodeValueAtActualCandidateCursor
{
    size_t actualCursor = self.actualCandidateCursorIndex;
    size_t endCursorIndex = 0;
    auto nodeIter = _latestWalk.findNodeAt(actualCursor, &endCursorIndex);
    if (nodeIter == _latestWalk.nodes.cend()) {
        return nil;
    }
    return @((*nodeIter)->currentUnigram().value().c_str());
}

// MARK: - Current output helpers

- (std::string)_currentLayoutCpp
{
    NSString *keyboardLayoutName = Preferences.keyboardLayoutName;
    std::string layout = std::string(keyboardLayoutName.UTF8String) + "_";
    return layout;
}

- (NSString *)currentLayout
{
    return @([self _currentLayoutCpp].c_str());
}

- (NSArray<NSString *> *)currentReadings
{
    NSMutableArray *readingsArray = [[NSMutableArray alloc] init];
    for (const auto& reading : _grid->readings()) {
        [readingsArray addObject:@(reading.c_str())];
    }
    return readingsArray;
}

- (NSString *)currentBpmfReading
{
    NSArray *readings = [self currentReadings];
    return [readings componentsJoinedByString:@"-"];
}

- (NSString *)currentHtmlRuby
{
    std::string composed;
    for (const auto& node : _latestWalk.nodes) {
        std::string key = node->reading();
        std::replace(key.begin(), key.end(), '-', ' ');
        std::string value = node->value();

        if (key.rfind(std::string("_"), 0) == 0) {
            composed += value;
        } else {
            composed += "<ruby>";
            composed += value;
            composed += "<rp>(</rp><rt>" + key + "</rt><rp>)</rp>";
            composed += "</ruby>";
        }
    }
    return [NSString stringWithUTF8String:composed.c_str()];
}

- (NSString *)currentBrailleWithType:(NSInteger)type
{
    BrailleType brailleType = (BrailleType)type;
    NSMutableString *composingBuffer = [[NSMutableString alloc] init];
    for (const auto& node : _latestWalk.nodes) {
        std::string value = node->currentUnigram().value();
        std::string reading = node->reading();
        if (reading[0] == '_') {
            NSString *punctuation = [[NSString alloc] initWithUTF8String:value.c_str()];
            NSString *converted = [BopomofoBrailleConverter convertFromBopomofo:punctuation type:brailleType];
            [composingBuffer appendString:converted];
        } else {
            std::string delimiter = "-";
            size_t pos = 0;
            std::string token;
            while ((pos = reading.find(delimiter)) != std::string::npos) {
                token = reading.substr(0, pos);
                NSString *tokenString = [[NSString alloc] initWithUTF8String:token.c_str()];
                NSString *converted = [BopomofoBrailleConverter convertFromBopomofo:tokenString type:brailleType];
                [composingBuffer appendString:converted];
                reading.erase(0, pos + delimiter.length());
            }
            NSString *tokenString = [[NSString alloc] initWithUTF8String:reading.c_str()];
            NSString *converted = [BopomofoBrailleConverter convertFromBopomofo:tokenString type:brailleType];
            [composingBuffer appendString:converted];
        }
    }
    return composingBuffer;
}

- (NSString *)currentHanyuPinyin
{
    NSMutableArray *array = [[NSMutableArray alloc] init];
    for (const auto& node : _latestWalk.nodes) {
        std::string key = node->reading();
        std::string value = node->value();

        if (key.rfind(std::string("_"), 0) == 0) {
            [array addObject:[NSString stringWithUTF8String:value.c_str()]];
        } else {
            size_t start = 0, end;
            std::string delimiter = "-";
            while ((end = key.find(delimiter, start)) != std::string::npos) {
                auto component = key.substr(start, end - start);
                Formosa::Mandarin::BopomofoSyllable syllable = Formosa::Mandarin::BopomofoSyllable::FromComposedString(component);
                std::string hanyuPinyin = syllable.HanyuPinyinString(false, false);
                [array addObject:[NSString stringWithUTF8String:hanyuPinyin.c_str()]];
                start = end + 1;
            }
            auto component = key.substr(start);
            Formosa::Mandarin::BopomofoSyllable syllable = Formosa::Mandarin::BopomofoSyllable::FromComposedString(component);
            std::string hanyuPinyin = syllable.HanyuPinyinString(false, false);
            [array addObject:[NSString stringWithUTF8String:hanyuPinyin.c_str()]];
        }
    }
    return [array componentsJoinedByString:@""];
}

// MARK: - Cursor utilities

- (NSInteger)actualCandidateCursorIndex
{
    return [self computeActualCursorIndex:_grid->cursor()];
}

- (NSInteger)cursorIndex
{
    return _grid->cursor();
}

- (NSInteger)computeActualCursorIndex:(NSInteger)cursor
{
    if ((size_t)cursor == _grid->length() && cursor > 0) {
        return cursor - 1;
    }

    if (!Preferences.selectPhraseAfterCursorAsCandidate && cursor > 0) {
        return cursor - 1;
    }

    return cursor;
}

@end

@implementation BuildAssociatedPhraseParams
@synthesize previousState;
@synthesize prefixCursorIndex;
@synthesize reading;
@synthesize value;
@synthesize candidateIndex;
@synthesize useVerticalMode;
@synthesize autoTriggered;
@end
