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

#import "ServiceProviderInputHelperBridge.h"
#import "LanguageModelManagerBridge+Privates.h"
#import "Mandarin.h"
#import "reading_grid.h"

@interface ServiceProviderInputHelperBridge()
{
    std::shared_ptr<Formosa::Gramambular2::LanguageModel> _emptySharedPtr;
    Formosa::Gramambular2::ReadingGrid *_grid;
}
@end

@implementation ServiceProviderInputHelperBridge

- (void)dealloc
{
    delete _grid;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        std::shared_ptr<Formosa::Gramambular2::LanguageModel> lm(_emptySharedPtr, [LanguageModelManagerBridge languageModelMcBopomofo]);
        _grid = new Formosa::Gramambular2::ReadingGrid(lm);
    }
    return self;
}

- (void)insertReading:(NSString *)reading
{
    _grid->insertReading(reading.UTF8String);
}

- (NSString *)commitAndReset
{
    Formosa::Gramambular2::ReadingGrid::WalkResult latestWalk = _grid->walk();
    std::string output;
    for (const auto& node : latestWalk.nodes) {
        output += node->value();
    }
    _grid->clear();
    return [NSString stringWithUTF8String:output.c_str()];
}

- (void)reset
{
    _grid->clear();
}

- (NSString *)convertReadingToHanyuPinyin:(NSString *)reading
{
    std::string readingStr = std::string([reading UTF8String]);
    Formosa::Mandarin::BopomofoSyllable syllable = Formosa::Mandarin::BopomofoSyllable::FromComposedString(readingStr);
    std::string hanyuPinyin = syllable.HanyuPinyinString(false, false);
    return [[NSString alloc] initWithUTF8String:hanyuPinyin.c_str()];
}

@end
