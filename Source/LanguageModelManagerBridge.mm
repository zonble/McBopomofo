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

#import "LanguageModelManagerBridge+Privates.h"
#import "McBopomofo-Swift.h"

#include "AssociatedPhrasesV2.h"
#include "UTF8Helper.h"

@import OpenCCBridge;

static const int kUserOverrideModelCapacity = 500;
static const double kObservedOverrideHalflife = 5400.0; // 1.5 hr.

static McBopomofo::McBopomofoLM gLanguageModelMcBopomofo;
static McBopomofo::McBopomofoLM gLanguageModelPlainBopomofo;
static McBopomofo::UserOverrideModel gUserOverrideModel(kUserOverrideModelCapacity, kObservedOverrideHalflife);
static McBopomofo::VariantAnnotator gVariantAnnotator;

static void LTLoadLanguageModelFile(NSString *filenameWithoutExtension, McBopomofo::McBopomofoLM& lm)
{
    Class cls = NSClassFromString(@"McBopomofoInputMethodController");
    NSString *dataPath = [[NSBundle bundleForClass:cls] pathForResource:filenameWithoutExtension ofType:@"txt"];
    lm.loadLanguageModel(dataPath.UTF8String);
}

static void LTLoadAssociatedPhrases(McBopomofo::McBopomofoLM& lm)
{
    Class cls = NSClassFromString(@"McBopomofoInputMethodController");
    NSString *dataPath = [[NSBundle bundleForClass:cls] pathForResource:@"associated-phrases-v2" ofType:@"txt"];
    lm.loadAssociatedPhrasesV2(dataPath.UTF8String);
}

static void LTLoadVariantAnnotatorData()
{
    Class cls = NSClassFromString(@"McBopomofoInputMethodController");
    NSString *puaDataPath = [[NSBundle bundleForClass:cls] pathForResource:@"bpmfvs-pua" ofType:@"txt"];
    if (puaDataPath == nil) {
        NSLog(@"Error: No PUA data found in bundle");
        return;
    }

    NSString *variantsDataPath = [[NSBundle bundleForClass:cls] pathForResource:@"bpmfvs-variants" ofType:@"txt"];
    if (variantsDataPath == nil) {
        NSLog(@"Error: No variants data found in bundle");
        return;
    }

    BOOL puaLoaded = gVariantAnnotator.loadPUAFile(puaDataPath.UTF8String);
    BOOL variantsLoaded = gVariantAnnotator.loadVariantsFile(variantsDataPath.UTF8String);
    if (!gVariantAnnotator.loaded()) {
        NSLog(@"Error: VariantAnnotator not ready, puaLoaded: %d, variantsLoaded: %d", puaLoaded, variantsLoaded);
    }
}

@implementation LanguageModelManagerBridge

+ (McBopomofo::McBopomofoLM *)languageModelMcBopomofo
{
    return &gLanguageModelMcBopomofo;
}

+ (McBopomofo::McBopomofoLM *)languageModelPlainBopomofo
{
    return &gLanguageModelPlainBopomofo;
}

+ (McBopomofo::UserOverrideModel *)userOverrideModel
{
    return &gUserOverrideModel;
}

+ (McBopomofo::VariantAnnotator *)variantAnnotator
{
    return &gVariantAnnotator;
}

+ (void)loadDataModels
{
    if (!gLanguageModelMcBopomofo.isDataModelLoaded()) {
        LTLoadLanguageModelFile(@"data", gLanguageModelMcBopomofo);
    }
    if (!gLanguageModelMcBopomofo.isAssociatedPhrasesV2Loaded()) {
        LTLoadAssociatedPhrases(gLanguageModelMcBopomofo);
    }

    if (!gLanguageModelPlainBopomofo.isDataModelLoaded()) {
        LTLoadLanguageModelFile(@"data-plain-bpmf", gLanguageModelPlainBopomofo);
    }
    if (!gLanguageModelPlainBopomofo.isAssociatedPhrasesV2Loaded()) {
        LTLoadAssociatedPhrases(gLanguageModelPlainBopomofo);
    }
    if (!gVariantAnnotator.loaded()) {
        LTLoadVariantAnnotatorData();
    }
}

+ (void)loadDataModel:(InputMode)mode
{
    if ([mode isEqualToString:InputModeBopomofo]) {
        if (!gLanguageModelMcBopomofo.isDataModelLoaded()) {
            LTLoadLanguageModelFile(@"data", gLanguageModelMcBopomofo);
        }
        if (!gLanguageModelMcBopomofo.isAssociatedPhrasesV2Loaded()) {
            LTLoadAssociatedPhrases(gLanguageModelMcBopomofo);
        }
        if (!gVariantAnnotator.loaded()) {
            LTLoadVariantAnnotatorData();
        }
    }

    if ([mode isEqualToString:InputModePlainBopomofo]) {
        if (!gLanguageModelPlainBopomofo.isDataModelLoaded()) {
            LTLoadLanguageModelFile(@"data-plain-bpmf", gLanguageModelPlainBopomofo);
        }
        if (!gLanguageModelPlainBopomofo.isAssociatedPhrasesV2Loaded()) {
            LTLoadAssociatedPhrases(gLanguageModelPlainBopomofo);
        }
        if (!gVariantAnnotator.loaded()) {
            LTLoadVariantAnnotatorData();
        }
    }
}

+ (void)loadUserPhrasesWithMcBopomofoPath:(NSString *)mcBopomofoPath
                      excludedMcBopomofoPath:(NSString *)excludedMcBopomofoPath
                       plainBopomofoPath:(nullable NSString *)plainBopomofoPath
                  excludedPlainBopomofoPath:(NSString *)excludedPlainBopomofoPath
{
    gLanguageModelMcBopomofo.loadUserPhrases(mcBopomofoPath.UTF8String, excludedMcBopomofoPath.UTF8String);
    gLanguageModelPlainBopomofo.loadUserPhrases(plainBopomofoPath ? plainBopomofoPath.UTF8String : NULL,
        excludedPlainBopomofoPath.UTF8String);
}

+ (void)loadUserPhraseReplacementWithPath:(NSString *)path
{
    gLanguageModelMcBopomofo.loadPhraseReplacementMap(path.UTF8String);
}

+ (void)setupDataModelValueConverter
{
    auto macroConverter = [](const std::string& input) {
        NSString *inputText = @(input.c_str());
        NSString *handled = [[InputMacroController shared] handle:inputText];
        return std::string(handled.UTF8String);
    };

    auto converter = [](const std::string& input) {
        if (!Preferences.chineseConversionEnabled) {
            return input;
        }

        if (Preferences.chineseConversionStyle == 0) {
            return input;
        }

        NSString *text = [[OpenCCBridge sharedInstance] convertToSimplified:@(input.c_str())];
        return std::string(text.UTF8String);
    };

    gLanguageModelMcBopomofo.setMacroConverter(macroConverter);
    gLanguageModelMcBopomofo.setExternalConverter(converter);
    gLanguageModelPlainBopomofo.setExternalConverter(converter);
}

+ (BOOL)checkIfUserPhraseExist:(NSString *)userPhrase key:(NSString *)key
{
    std::string unigramKey(key.UTF8String);
    auto unigrams = gLanguageModelMcBopomofo.getUnigrams(unigramKey);
    std::string userPhraseString(userPhrase.UTF8String);
    for (const auto& unigram : unigrams) {
        if (unigram.value() == userPhraseString) {
            return YES;
        }
    }
    return NO;
}

+ (BOOL)phraseReplacementEnabled
{
    return gLanguageModelMcBopomofo.phraseReplacementEnabled();
}

+ (void)setPhraseReplacementEnabled:(BOOL)phraseReplacementEnabled
{
    gLanguageModelMcBopomofo.setPhraseReplacementEnabled(phraseReplacementEnabled);
}

+ (nullable NSString *)readingFor:(NSString *)phrase
{
    if (!gLanguageModelMcBopomofo.isDataModelLoaded()) {
        [self loadDataModel:InputModeBopomofo];
    }

    std::string reading = gLanguageModelMcBopomofo.getReading(phrase.UTF8String);
    return !reading.empty() ? @(reading.c_str()) : nil;
}

+ (NSString *)annotateVariantForCharacters:(NSString *)inCharacters readings:(NSString *)inReadings
{
    McBopomofo::VariantAnnotator *annotator = LanguageModelManagerBridge.variantAnnotator;
    if (!annotator || !annotator->loaded()) {
        return inCharacters;
    }

    std::string value(inCharacters.UTF8String);
    std::string readingString(inReadings.UTF8String);
    std::vector<std::string> characters = McBopomofo::Split(value);
    std::vector<std::string> readings = McBopomofo::AssociatedPhrasesV2::SplitReadings(readingString);

    McBopomofo::VariantAnnotator::CombinedResult result = LanguageModelManagerBridge.variantAnnotator->annotate(characters,
                                                                                                          readings);
    return [[NSString alloc] initWithUTF8String:result.annotatedString.c_str()];
}

@end
