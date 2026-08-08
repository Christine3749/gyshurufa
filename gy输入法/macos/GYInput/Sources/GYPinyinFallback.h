// GYPinyinFallback — pure string logic for the 5×5 candidate-page fallback
// ladder (spec §5.2: "gei → ge"), ported from Windows PinyinEngine.cpp's
// Lookup(). No Rime, no ivars, so the ladder itself is unit-testable
// independent of librime (see GYInputTests/GYPinyinFallbackTests.m).

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#if defined(__cplusplus)
extern "C" {
#endif

/// Computes the next, shorter pinyin fallback code by dropping the last
/// character and any now-dangling trailing syllable-separator apostrophes
/// (typing "ni'hao" and falling back from it must not leave a bare
/// trailing "'"). Returns nil once the result would drop below two
/// characters — a single letter is too noisy to be a usable fallback
/// surface (spec §5.2's "仍不足时继续按定义好的回退阶梯" stops here, not at
/// an empty string). Lowercases the input first, matching how pinyin codes
/// are normalized elsewhere in this pipeline.
//
// extern "C" above: GYRimeBridge.mm is Objective-C++, so without this guard
// it would look for a C++-name-mangled symbol while GYPinyinFallback.m (a
// plain .m, compiled as C/Objective-C) exports a plain C symbol -- a link
// failure, not a compile error, so it would otherwise surface far from its
// actual cause.
NSString *_Nullable GYNextFallbackPinyinCode(NSString *code);

#if defined(__cplusplus)
}
#endif

NS_ASSUME_NONNULL_END
