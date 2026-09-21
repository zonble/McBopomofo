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

#import <Foundation/Foundation.h>
#import "InputMode.h"

@class InputState;
@class InputStateInputting;
@class InputStateChoosingCandidate;
@class KeyHandlerInput;

NS_ASSUME_NONNULL_BEGIN


@interface BuildAssociatedPhraseParams: NSObject
@property (strong, nonatomic) id previousState;
@property (assign, nonatomic) NSUInteger prefixCursorIndex;
@property (strong, nonatomic) NSString *reading;
@property (strong, nonatomic) NSString *value;
@property (assign, nonatomic) NSInteger candidateIndex;
@property (assign, nonatomic) BOOL useVerticalMode;
@property (assign, nonatomic) BOOL autoTriggered;
@end

/// ObjC++ bridge that owns all C++ state for KeyHandler.
@interface KeyHandlerCxxBridge : NSObject

// MARK: - Lifecycle
- (void)clear;
- (void)syncWithPreferences;
@property (strong, nonatomic) InputMode inputMode;

// MARK: - BPMF reading buffer
@property (readonly) BOOL bpmfReadingBufferIsEmpty;
@property (readonly) BOOL bpmfReadingBufferHasToneMarker;
@property (readonly) BOOL bpmfReadingBufferHasToneMarkerOnly;
- (BOOL)bpmfReadingBufferIsValidKey:(UniChar)charCode;
- (void)bpmfReadingBufferCombineKey:(UniChar)charCode;
- (void)bpmfReadingBufferClear;
- (void)bpmfReadingBufferBackspace;
- (NSString *)bpmfComposedReading;

// MARK: - Grid
@property (readwrite) NSInteger gridCursor;
@property (readonly) NSInteger gridLength;
- (void)gridInsertReading:(NSString *)reading;
- (void)gridDeleteReadingBeforeCursor;
- (void)gridDeleteReadingAfterCursor;
- (void)gridClear;
- (NSArray<NSString *> *)gridReadings;

// MARK: - Walk and language model
- (void)walk;
- (BOOL)hasUnigrams:(NSString *)key;
- (NSArray<NSString *> *)unigramsForKey:(NSString *)key;
- (void)applyUserOverrideModelAfterWalk;

// MARK: - State builders
- (InputStateInputting *)buildInputtingState;
- (InputStateChoosingCandidate *)buildCandidateStateFromInputtingState:(InputStateInputting *)inputting useVerticalMode:(BOOL)useVerticalMode;
- (nullable InputState *)buildAssociatedPhrasePlainStateWithReading:(NSString *)reading value:(NSString *)value useVerticalMode:(BOOL)useVerticalMode;
- (nullable InputState *)buildAssociatedPhraseStateWithParams:(BuildAssociatedPhraseParams *)params;

// MARK: - Complex C++ operations (stay entirely in bridge)
- (void)fixNodeWithReading:(NSString *)reading value:(NSString *)value originalCursorIndex:(NSUInteger)idx useMoveCursorAfterSelectionSetting:(BOOL)flag NS_SWIFT_NAME(fixNode(reading:value:originalCursorIndex:useMoveCursorAfterSelectionSetting:));
- (void)fixNodeForAssociatedPhraseWithPrefixAt:(NSUInteger)idx prefixReading:(NSString *)pfxReading prefixValue:(NSString *)pfxValue associatedPhraseReading:(NSString *)phraseReading associatedPhraseValue:(NSString *)phraseValue;
- (BOOL)handleAssociatedPhraseWithState:(InputState *)state useVerticalMode:(BOOL)vm stateCallback:(void(^)(InputState*))sc errorCallback:(void(^)(void))ec autoTriggered:(BOOL)at maxCandidateCount:(NSUInteger)maxCount;
- (BOOL)handleTabWithState:(InputState *)state shiftIsHold:(BOOL)shift stateCallback:(void(^)(InputState*))sc errorCallback:(void(^)(void))ec;
- (BOOL)handlePunctuation:(NSString *)punc state:(InputState *)state useVerticalMode:(BOOL)vm stateCallback:(void(^)(InputState*))sc errorCallback:(void(^)(void))ec;
- (BOOL)shouldAutoSelectCandidateForCharCode:(UniChar)charCode controlHold:(BOOL)controlHold halfWidthPunctuationEnabled:(BOOL)halfWidth;
- (nullable InputStateInputting *)tryChangePriorToneWithCharCode:(UniChar)charCode;
- (NSArray<NSString *> *)collectUserFileIssues;

// MARK: - Walk node access
@property (readonly) BOOL walkNodeIsOverriddenAtActualCandidateCursor;
@property (readonly, nullable) NSString *walkNodeReadingAtActualCandidateCursor;
@property (readonly, nullable) NSString *walkNodeValueAtActualCandidateCursor;

// MARK: - Current output helpers
- (NSString *)currentLayout;
- (NSArray<NSString *> *)currentReadings;
- (NSString *)currentBpmfReading;
- (NSString *)currentHtmlRuby;
- (NSString *)currentBrailleWithType:(NSInteger)type;
- (NSString *)currentHanyuPinyin;

// MARK: - Cursor utilities
@property (readonly) NSInteger actualCandidateCursorIndex;
@property (readonly) NSInteger cursorIndex;
- (NSInteger)computeActualCursorIndex:(NSInteger)cursor;

@end

NS_ASSUME_NONNULL_END
