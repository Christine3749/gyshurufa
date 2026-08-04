#import "GYLexicon.h"

@implementation GYLexicon

+ (NSDictionary<NSString *, NSArray<NSString *> *> *)entries {
  return @{
    @"ai": @[@"爱|愛", @"矮|矮", @"哎|哎", @"唉|唉"],
    @"bu": @[@"不|不", @"不对|不對", @"不能|不能", @"不会|不會"],
    @"daxue": @[@"大学|大學", @"大学生|大學生"],
    @"diannao": @[@"电脑|電腦", @"电脑上|電腦上"],
    @"duibuqi": @[@"对不起|對不起", @"对不住|對不住"],
    @"gongzuo": @[@"工作|工作", @"工作中|工作中"],
    @"guo": @[@"国|國", @"过|過", @"果|果", @"锅|鍋"],
    @"haoma": @[@"好吗|好嗎", @"号码|號碼"],
    @"hen": @[@"很|很", @"狠|狠", @"恨|恨"],
    @"hao": @[@"好|好", @"号|號", @"好啊|好啊", @"好的|好的"],
    @"jintian": @[@"今天|今天", @"今天的|今天的"],
    @"keyi": @[@"可以|可以", @"可以吗|可以嗎"],
    @"ma": @[@"吗|嗎", @"妈|媽", @"嘛|嘛", @"马|馬"],
    @"meiguanxi": @[@"没关系|沒關係", @"没有关系|沒有關係"],
    @"mingtian": @[@"明天|明天", @"明天见|明天見"],
    @"ni": @[@"你|你", @"呢|呢", @"泥|泥", @"拟|擬"],
    @"nihao": @[@"你好|你好", @"你号|你號", @"拟好|擬好"],
    @"nin": @[@"您|您", @"恁|恁"],
    @"pengyou": @[@"朋友|朋友", @"好朋友|好朋友"],
    @"qing": @[@"请|請", @"情|情", @"青|青", @"轻|輕"],
    @"qingwen": @[@"请问|請問", @"请问一下|請問一下"],
    @"shangban": @[@"上班|上班", @"上班了|上班了"],
    @"shenme": @[@"什么|什麼", @"什么的|什麼的"],
    @"shi": @[@"是|是", @"时|時", @"事|事", @"市|市"],
    @"shijian": @[@"时间|時間", @"世界|世界", @"事件|事件"],
    @"shurufa": @[@"输入法|輸入法", @"输入方法|輸入方法"],
    @"tianqi": @[@"天气|天氣", @"天气好|天氣好"],
    @"wo": @[@"我|我", @"我们|我們", @"我的|我的", @"我想|我想"],
    @"women": @[@"我们|我們", @"我们的|我們的"],
    @"xiexie": @[@"谢谢|謝謝", @"谢谢你|謝謝你"],
    @"xihuan": @[@"喜欢|喜歡", @"喜欢你|喜歡你"],
    @"xuexi": @[@"学习|學習", @"学生|學生", @"学校|學校"],
    @"zaijian": @[@"再见|再見", @"再见了|再見了"],
    @"zenme": @[@"怎么|怎麼", @"怎么样|怎麼樣"],
    @"zhongguo": @[@"中国|中國", @"中国人|中國人", @"中国的|中國的"],
    @"zhongwen": @[@"中文|中文", @"中文输入|中文輸入", @"中文输入法|中文輸入法"],
  };
}

+ (NSString *)normalizedCode:(NSString *)text {
  NSMutableString *result = [NSMutableString string];
  for (NSUInteger index = 0; index < text.length; index++) {
    unichar character = [text characterAtIndex:index];
    if (character == '\'') continue;
    if (character >= 'A' && character <= 'Z') character += 'a' - 'A';
    if (character < 'a' || character > 'z') return @"";
    [result appendFormat:@"%C", character];
  }
  return result;
}

+ (BOOL)isChinesePhrase:(NSString *)text {
  if (text.length == 0 || text.length > 12) return NO;
  for (NSUInteger index = 0; index < text.length; index++) {
    unichar c = [text characterAtIndex:index];
    if (!((c >= 0x3400 && c <= 0x4DBF) || (c >= 0x4E00 && c <= 0x9FFF) ||
          (c >= 0xF900 && c <= 0xFAFF))) return NO;
  }
  return YES;
}

+ (NSArray<NSString *> *)candidatesForCode:(NSString *)code mode:(GYInputMode)mode {
  if (!GYInputModeUsesChinese(mode)) return @[];
  NSArray<NSString *> *pairs = [self entries][[self normalizedCode:code]] ?: @[];
  NSMutableOrderedSet<NSString *> *result = [NSMutableOrderedSet orderedSet];
  for (NSString *pair in pairs) {
    NSArray<NSString *> *forms = [pair componentsSeparatedByString:@"|"];
    NSString *candidate = forms[MIN((NSUInteger)mode, forms.count - 1)];
    if ([self isChinesePhrase:candidate]) [result addObject:candidate];
    if (result.count == 75) break;
  }
  return result.array;
}

@end
