import { DictionaryEntry } from '../types';

export const INITIAL_DICTIONARY: Record<string, string[]> = {
  'keyle': ['可以让', '客运量', '可用来', '柯有伦', '可又来', '客流量', '不可以了', '酷欧拉'],
  'ce': ['测试', '侧重', '策略', '测验', '册', '侧', '策', '测'],
  'zhongguo': ['中国', '种过', '重过', '忠国', '终过', '中国队', '中国人', '中国龙'],
  'gongzuo': ['工作', '工作量', '工作人员', '公作', '攻作', '工作日', '工作站'],
  'pinyin': ['拼音', '频引', '品饮', '拼音输入法', '拼音字母', '拼音图'],
  'guge': ['谷歌', '骨骼', '谷鸽', '谷歌拼音', '谷歌地图', '谷歌浏览器', '谷歌搜索'],
  'shuru': ['输入', '输入法', '数如', '数出', '输入框', '输入设备'],
  'chuda': ['触达', '出达', '初达', '触达率', '处大', '出打'],
  'daziyuyan': ['打字语言', '大字语言', '打字预研', '搭自语言'],
  'nide': ['你的', '妮的', '拟的', '逆德', '匿的', '呢得'],
  'xiantian': ['先天', '现代', '仙天', '显天', '先天性', '线天'],
  'nihao': ['你好', '拟好', '泥好', '你好呀', '你好啊', '泥豪'],
  'xiexie': ['谢谢', '写写', '谢谢你', '血血', '斜斜'],
  'sheji': ['设计', '生机', '设籍', '射击', '设计师', '设计稿', '设计图'],
  'diannao': ['电脑', '电脑版', '电脑房', '电脑桌', '电脑软件'],
  'chuangxin': ['创新', '创薪', '床新', '窗芯', '创新力', '创新者'],
  'yingyong': ['应用', '硬用', '英勇', '应用程序', '应用商店', '应用层'],
  'kaifa': ['开发', '开法', '凯发', '开发者', '开发区', '开发商'],
  'jizhun': ['基准', '极准', '记准', '基准线', '基准点'],
  'fuke': ['复刻', '副科', '服客', '复刻版', '复刻品'],
  'huanjing': ['环境', '幻境', '换境', '环境保护', '环境音'],
  'tiankong': ['天空', '填空', '天孔', '天空之城', '天空蓝'],
  'zhuomian': ['桌面', '琢面', '桌面版', '桌面图标', '桌面壁纸'],
};

// Fallback algorithm for arbitrary pinyin inputs
export function getCandidatesForPinyin(pinyin: string, customDict?: Record<string, string[]>): string[] {
  const clean = pinyin.toLowerCase().trim();
  if (!clean) return [];

  const combinedDict = { ...INITIAL_DICTIONARY, ...(customDict || {}) };

  // Exact match
  if (combinedDict[clean]) {
    return combinedDict[clean];
  }

  // Prefix or partial match search
  const matchedKeys = Object.keys(combinedDict).filter(k => k.startsWith(clean) || clean.startsWith(k));
  if (matchedKeys.length > 0) {
    const results: string[] = [];
    for (const key of matchedKeys) {
      results.push(...combinedDict[key]);
    }
    // Unique
    const unique = Array.from(new Set(results));
    if (unique.length > 0) return unique;
  }

  // Generate synthetic character candidates based on pinyin letters
  return [
    `${clean} (候选1)`,
    `${clean} (候选2)`,
    `${clean} (候选3)`,
    `${clean} (候选4)`,
    `${clean} (候选5)`,
  ];
}
