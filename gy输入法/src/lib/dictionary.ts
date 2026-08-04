import { CandidateItem } from '../types';

interface DictionaryMap {
  [pinyin: string]: string[];
}

// Built-in high priority dictionary database for GY Shurufa
const BUILTIN_DICTIONARY: DictionaryMap = {
  gyshurufa: [
    'GY输入法',
    'GSYEN输入法',
    '输入法',
    '高效输入法',
    '国盛研输入法',
    '极速输入法',
    '本地输入法',
    '工业输入法',
    '光影输入法',
  ],
  gsyen: ['GSYEN', '国盛研', '高效能', '智研', '高盛源', '古森严'],
  shurufa: ['输入法', '数学法', '舒适法', '书书法', '极速法'],
  pingyin: ['拼音', '评议', '平音', '品音', '频引'],
  ceshi: ['测试', '策划', '侧视', '测试'],
  cehi: ['测试', '策划', '侧黑'],
  bendi: ['本地优先', '本地', '笨地', '奔地'],
  anquan: ['安全', '暗泉', '安全第一', '按期'],
  yinsi: ['隐私', '隐斯', '印斯'],
  ai: ['AI 辅助', '爱', '智能', '艾', '埃', '矮', '哀', '碍'],
  nihao: ['你好', '拟好', '泥耗', '你号'],
  gaoxiao: ['高效', '高校', '搞笑', '高小'],
  kuai: ['快', '块', '脍', '筷'],
  zhun: ['准', '谆', '准许', '准则'],
  chuangxin: ['创新', '创芯', '闯心'],
  windows: ['Windows 11', 'Windows 10', 'Windows', '窗口'],
  gyshurufaai: ['GY输入法 AI助手', 'GY输入法', 'GSYEN输入法'],
};

// Pinyin syllables list for dynamic fuzzy segmenting
const PINYIN_SYLLABLES = [
  'a', 'ai', 'an', 'ang', 'ao', 'ba', 'bai', 'ban', 'bang', 'bao', 'bei', 'ben', 'beng', 'bi', 'bian', 'biao', 'bie', 'bin', 'bing', 'bo', 'bu',
  'ca', 'cai', 'can', 'cang', 'cao', 'ce', 'cen', 'ceng', 'cha', 'chai', 'chan', 'chang', 'chao', 'che', 'chen', 'cheng', 'chi', 'chong', 'chou', 'chu', 'chua', 'chuai', 'chuan', 'chuang', 'chui', 'chun', 'chuo', 'ci', 'cong', 'cou', 'cu', 'cuan', 'cui', 'cun', 'cuo',
  'da', 'dai', 'dan', 'dang', 'dao', 'de', 'dei', 'deng', 'di', 'dian', 'diao', 'die', 'ding', 'diu', 'dong', 'dou', 'du', 'duan', 'dui', 'dun', 'duo',
  'e', 'ei', 'en', 'eng', 'er', 'fa', 'fan', 'fang', 'fei', 'fen', 'feng', 'fo', 'fou', 'fu',
  'ga', 'gai', 'gan', 'gang', 'gao', 'ge', 'gei', 'gen', 'geng', 'gong', 'gou', 'gu', 'gua', 'guai', 'guan', 'guang', 'gui', 'gun', 'guo',
  'ha', 'hai', 'han', 'hang', 'hao', 'he', 'hei', 'hen', 'heng', 'hong', 'hou', 'hu', 'hua', 'huai', 'huan', 'huang', 'hui', 'hun', 'huo',
  'ji', 'jia', 'jian', 'jiang', 'jiao', 'jie', 'jin', 'jing', 'jiong', 'jiu', 'ju', 'juan', 'jue', 'jun',
  'ka', 'kai', 'kan', 'kang', 'kao', 'ke', 'ken', 'keng', 'kong', 'kou', 'ku', 'kua', 'kuai', 'kuan', 'kuang', 'kui', 'kun', 'kuo',
  'la', 'lai', 'lan', 'lang', 'lao', 'le', 'lei', 'leng', 'li', 'lia', 'lian', 'liang', 'liao', 'lie', 'lin', 'ling', 'liu', 'long', 'lou', 'lu', 'lv', 'luan', 'lue', 'lun', 'luo',
  'ma', 'mai', 'man', 'mang', 'mao', 'me', 'mei', 'men', 'meng', 'mi', 'mian', 'miao', 'mie', 'min', 'ming', 'miu', 'mo', 'mou', 'mu',
  'na', 'nai', 'nan', 'nang', 'nao', 'ne', 'nei', 'nen', 'neng', 'ni', 'nian', 'niang', 'niao', 'nie', 'nin', 'ning', 'niu', 'nong', 'nou', 'nu', 'nv', 'nuan', 'nue', 'nuo',
  'ou', 'pa', 'pai', 'pan', 'pang', 'pao', 'pei', 'pen', 'peng', 'pi', 'pian', 'piao', 'pie', 'pin', 'ping', 'po', 'pou', 'pu',
  'qi', 'qia', 'qian', 'qiang', 'qiao', 'qie', 'qin', 'qing', 'qiong', 'qiu', 'qu', 'quan', 'que', 'qun',
  'ran', 'rang', 'rao', 're', 'ren', 'reng', 'ri', 'rong', 'rou', 'ru', 'ruan', 'rui', 'run', 'ruo',
  'sa', 'sai', 'san', 'sang', 'sao', 'se', 'sen', 'seng', 'sha', 'shai', 'shan', 'shang', 'shao', 'she', 'shei', 'shen', 'sheng', 'shi', 'shou', 'shu', 'shua', 'shuai', 'shuan', 'shuang', 'shui', 'shun', 'shuo', 'si', 'song', 'sou', 'su', 'suan', 'sui', 'sun', 'suo',
  'ta', 'tai', 'tan', 'tang', 'tao', 'te', 'teng', 'ti', 'tian', 'tiao', 'tie', 'ting', 'tong', 'tou', 'tu', 'tuan', 'tui', 'tun', 'tuo',
  'wa', 'wai', 'wan', 'wang', 'wei', 'wen', 'weng', 'wo', 'wu',
  'xi', 'xia', 'xian', 'xiang', 'xiao', 'xie', 'xin', 'xing', 'xiong', 'xiu', 'xu', 'xuan', 'xue', 'xun',
  'ya', 'yan', 'yang', 'yao', 'ye', 'yi', 'yin', 'ying', 'yong', 'you', 'yu', 'yuan', 'yue', 'yun',
  'za', 'zai', 'zan', 'zang', 'zao', 'ze', 'zei', 'zen', 'zeng', 'zha', 'zhai', 'zhan', 'zhang', 'zhao', 'zhe', 'zhei', 'zhen', 'zheng', 'zhi', 'zhong', 'zhou', 'zhu', 'zhua', 'zhuai', 'zhuan', 'zhuang', 'zhui', 'zhun', 'zhuo', 'zi', 'zong', 'zou', 'zu', 'zuan', 'zui', 'zun', 'zuo'
];

/**
 * Format pinyin into readable syllable segments (e.g., gyshurufa -> gy | shu | ru | fa)
 */
export function formatPinyinSyllables(pinyin: string): string {
  if (!pinyin) return '';
  if (pinyin.toLowerCase().startsWith('gyshurufa')) {
    return 'gy | shu | ru | fa';
  }
  if (pinyin.toLowerCase().startsWith('gsyen')) {
    return 'G S Y E N';
  }

  // Basic syllable divider
  let remaining = pinyin.toLowerCase();
  const parts: string[] = [];
  
  while (remaining.length > 0) {
    let matched = false;
    // try longest syllable
    for (let len = Math.min(6, remaining.length); len >= 1; len--) {
      const sub = remaining.substring(0, len);
      if (PINYIN_SYLLABLES.includes(sub) || sub === 'gy' || sub === 'gsyen') {
        parts.push(sub);
        remaining = remaining.substring(len);
        matched = true;
        break;
      }
    }
    if (!matched) {
      parts.push(remaining.substring(0, 1));
      remaining = remaining.substring(1);
    }
  }

  return parts.join(' | ');
}

/**
 * Get candidate items for typed pinyin
 */
export function getCandidatesForPinyin(pinyinInput: string, maxCount = 9): CandidateItem[] {
  const cleanKey = pinyinInput.toLowerCase().trim().replace(/['\s]/g, '');
  
  if (!cleanKey) {
    return [];
  }

  // Exact or prefix match from built-in dictionary
  if (BUILTIN_DICTIONARY[cleanKey]) {
    const list = BUILTIN_DICTIONARY[cleanKey];
    return list.slice(0, maxCount).map((text, idx) => ({
      id: idx + 1,
      text,
      pinyin: cleanKey,
      isPrimary: idx === 0,
      frequency: 1000 - idx * 50,
    }));
  }

  // Try prefix matching
  const matchedKeys = Object.keys(BUILTIN_DICTIONARY).filter(k => k.startsWith(cleanKey) || cleanKey.startsWith(k));
  if (matchedKeys.length > 0) {
    const combined: string[] = [];
    matchedKeys.forEach(k => {
      BUILTIN_DICTIONARY[k].forEach(item => {
        if (!combined.includes(item)) combined.push(item);
      });
    });
    
    if (combined.length > 0) {
      return combined.slice(0, maxCount).map((text, idx) => ({
        id: idx + 1,
        text,
        pinyin: cleanKey,
        isPrimary: idx === 0,
        frequency: 800 - idx * 40,
      }));
    }
  }

  // Fallback dynamic candidate generator for unknown pinyin combinations
  const fallbackList = [
    `${cleanKey.toUpperCase()} 输入`,
    `GY-${cleanKey}`,
    `国盛研词库 [${cleanKey}]`,
    `快速候选词 A`,
    `快速候选词 B`,
  ];

  return fallbackList.slice(0, maxCount).map((text, idx) => ({
    id: idx + 1,
    text,
    pinyin: cleanKey,
    isPrimary: idx === 0,
    frequency: 500 - idx * 20,
  }));
}
