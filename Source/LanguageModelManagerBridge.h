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

NS_ASSUME_NONNULL_BEGIN

/// ObjC++ bridge class for LanguageModelManager. Holds all C++ global state
/// and exposes a pure-ObjC interface for use from Swift.
@interface LanguageModelManagerBridge : NSObject

+ (void)loadDataModels;
+ (void)loadDataModel:(InputMode)mode;
+ (void)loadUserPhrasesWithMcBopomofoPath:(NSString *)mcBopomofoPath
                      excludedMcBopomofoPath:(NSString *)excludedMcBopomofoPath
                       plainBopomofoPath:(nullable NSString *)plainBopomofoPath
                  excludedPlainBopomofoPath:(NSString *)excludedPlainBopomofoPath;
+ (void)loadUserPhraseReplacementWithPath:(NSString *)path;
+ (void)setupDataModelValueConverter;

+ (BOOL)checkIfUserPhraseExist:(NSString *)userPhrase key:(NSString *)key NS_SWIFT_NAME(checkIfExist(userPhrase:key:));
+ (BOOL)phraseReplacementEnabled;
+ (void)setPhraseReplacementEnabled:(BOOL)phraseReplacementEnabled;
+ (nullable NSString *)readingFor:(NSString *)phrase;
+ (NSString *)annotateVariantForCharacters:(NSString *)inCharacters readings:(NSString *)inReadings;

@end

NS_ASSUME_NONNULL_END
