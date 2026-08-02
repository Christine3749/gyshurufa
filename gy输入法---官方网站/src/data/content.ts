import { AIFeatureCard, EcosystemModule, TypingScenario, VersionInfo } from '../types';

export const BRAND_INFO = {
  name: 'GY输入法',
  englishName: 'GY Shurufa',
  parentBrand: 'GSYEN',
  domain: 'shurufa.wang',
  slogan: '让每一次输入，成为更好的开始。',
  subSlogan: 'GY输入法，GSYEN 智能工作生态的一部分。',
  platform: 'Windows 10 / Windows 11',
  version: 'v0.9.14',
  releaseDate: '2026年8月2日',
  fileSize: '9.57 MB',
  architecture: 'x64 / ARM64 原生架构',
  sha256: '6237EADD15C2B8F551990923CAE59F2759DEB6E705F440454C1E92DBE26DFF5E',
  // Keep the public download under the official site; Vercel proxies this path to the R2-backed Worker.
  downloadUrl: '/download/latest.exe'
};

export const TYPING_SCENARIOS: TypingScenario[] = [
  {
    id: 'hero-default',
    label: '日常高效输入',
    pinyinInput: 'gyshurufa',
    rawInputDisplay: 'gy shurufa',
    candidates: [
      { id: 1, word: 'GY输入法', tag: '品牌词库', description: '快捷输出精美品牌名' },
      { id: 2, word: '让每一次输入，成为更好的开始。', tag: 'Slogan长句', description: '一键自动联想完整标语' },
      { id: 3, word: '工业级本地轻量引擎', tag: '本地计算' },
      { id: 4, word: '高频专业词汇补全', tag: '本地智能' },
      { id: 5, word: '给予输入法', tag: '拼音候选' }
    ],
    aiSuggestion: {
      type: 'polish',
      title: '一键润色 (Alt + /)',
      original: '收到，我等下把方案发你看看。',
      result: '方案已整理完毕，稍后将发送给您审阅，请查收。'
    }
  },
  {
    id: 'hero-ai-polish',
    label: '职场公文润色',
    pinyinInput: 'gong zuo hui bao',
    rawInputDisplay: 'gong zuo hui bao',
    candidates: [
      { id: 1, word: '工作汇报', tag: '常用词' },
      { id: 2, word: '工作汇报ppt模版', tag: '联想短语' },
      { id: 3, word: '工作汇报总结要点', tag: '办公短语' },
      { id: 4, word: '工作汇报邮件模板', tag: '模版输出' }
    ],
    aiSuggestion: {
      type: 'polish',
      title: '商务体润色 (按 Tab 触发)',
      original: '这个项目下周做完。',
      result: '本项目的各项工作正稳步推进，预计将于下周完成最终交付。'
    }
  },
  {
    id: 'hero-ai-translate',
    label: '跨语言输入',
    pinyinInput: 'chuang xin xing xun su',
    rawInputDisplay: 'chuang xin xing xun su',
    candidates: [
      { id: 1, word: '创新性迅速', tag: '词组候选' },
      { id: 2, word: '创新型迅速迭代', tag: '技术常用' },
      { id: 3, word: 'chuangxinxing xunsu', tag: '拼音复刻' }
    ],
    aiSuggestion: {
      type: 'translate',
      title: '中英双语对译 (Alt + T)',
      original: '创新性迅速迭代的软件产品',
      result: 'Rapidly iterating innovative software products'
    }
  },
  {
    id: 'hero-snippet',
    label: '快捷指令与变量',
    pinyinInput: '/riqi',
    rawInputDisplay: '/riqi (快捷命令)',
    candidates: [
      { id: 1, word: '2026年8月1日', tag: '动态日期', description: '当前系统日期' },
      { id: 2, word: '2026-08-01 11:48', tag: '标准时间' },
      { id: 3, word: 'Saturday, August 1, 2026', tag: '英文日期' }
    ],
    aiSuggestion: {
      type: 'snippet',
      title: '自定义快捷变量',
      original: '/riqi',
      result: '自动识别并转换系统实时时间与模版短语'
    }
  }
];

export const CORE_VALUES = [
  {
    id: 'fast',
    title: '快：毫秒级响应，极致轻量',
    highlight: '< 0.8ms 首字响应',
    subtitle: '采用 C++ 高性能架构重构候选匹配，冷启动无停顿，系统内存占用低于 28MB。',
    metrics: [
      { label: '首字出词延迟', value: '< 0.8 ms', comp: '同行传统输入法约 15-30ms' },
      { label: '内存常驻占用', value: '~24 MB', comp: '同行传统输入法 120MB+' },
      { label: '启动加载耗时', value: '< 12 ms', comp: '几乎瞬间就绪' }
    ],
    features: [
      '低延迟无卡顿，适配 120Hz/240Hz 高刷新率显示器',
      '全新设计的高并发离线候选字典树 (Trie Struct)',
      'Windows 10/11 TSF 原生 API 深度优化'
    ]
  },
  {
    id: 'accurate',
    title: '准：深耕中文语境，智能纠错',
    highlight: '99.4% 拼音纠错准确率',
    subtitle: '基于上下文逻辑的轻量离线 N-gram 语言模型，容错率高，输入顺畅连贯。',
    metrics: [
      { label: '全拼长句精准度', value: '98.6%', comp: '支持一气呵成输入长句' },
      { label: '模糊音自动纠错', value: '智能识别', comp: '如 z/zh, c/ch, n/l 轻松辨识' },
      { label: '自适应个人词库', value: '本地学习', comp: '越用越贴合个人习惯' }
    ],
    features: [
      '支持双拼 (小鹤、自然码、拼音加加、微软双拼、智能ABC等)',
      '支持五笔及自定义形码扩展',
      '行业专业词库一键加载 (程序员、法律、医学、金融等)'
    ]
  },
  {
    id: 'secure',
    title: '安心：默认本地优先，隐私可控',
    highlight: '100% 基础输入完全离线',
    subtitle: '你的按键记录、个人词库、剪贴板历史默认只存在于你的 Windows 本地设备。',
    metrics: [
      { label: '核心输入数据', value: '100% 本地', comp: '无任何后台自动上传行为' },
      { label: '网络访问权限', value: '可一键禁网', comp: '防火墙策略完全兼容' },
      { label: 'AI 增值开关', value: '需主动按键', comp: '每一次 AI 调用均有透明提示' }
    ],
    features: [
      '不读取无相关权限，无后台弹窗广告，无弹窗推广',
      '个人词库支持本地加密备份与 JSON 原生导出导入',
      '开放网络审计日志，用户可随查每一笔外发请求'
    ]
  }
];

export const AI_FEATURES: AIFeatureCard[] = [
  {
    id: 'polish',
    iconName: 'Sparkles',
    title: '改写与润色',
    subtitle: '商务公文、学术表达、口语转书面',
    description: '在任意软件中打字完毕后，按下 Alt+/，AI 即刻提供多种语气改写建议，一键替换选中文本。',
    triggerKey: 'Alt + /',
    exampleOriginal: '这个需求今天干不完，明天再给你。',
    exampleProcessed: '由于当前任务细节尚需精细化调整，预计将于明日内提交最终成果，感谢您的理解。',
    tag: '语气切换'
  },
  {
    id: 'translate',
    iconName: 'Languages',
    title: '即时语境翻译',
    subtitle: '打字即翻译，多语言无缝切换',
    description: '无需打开浏览器或翻译软件，直接输入中文后按快捷键，立即原位替换为地道的英文、日文或法文。',
    triggerKey: 'Alt + T',
    exampleOriginal: '请确保系统在断网环境下也能正常运行。',
    exampleProcessed: 'Please ensure that the system operates normally even in an offline environment.',
    tag: '多语言'
  },
  {
    id: 'summarize',
    iconName: 'FileText',
    title: '长文摘要与提炼',
    subtitle: '选中文本，快速提取核心结论',
    description: '在阅读长邮件或报告时，选中文段即可在候选框中实时查看关键要点摘要与行动项。',
    triggerKey: 'Alt + S',
    exampleOriginal: '关于下季度季度预算的各部门评审会议，经过两个小时讨论，决定对营销费用削减15%，研发增加20%。',
    exampleProcessed: '【会议结论】1. 营销预算削减 15%；2. 研发预算增加 20%。',
    tag: '效率提炼'
  },
  {
    id: 'snippets',
    iconName: 'Zap',
    title: '智能快捷短语',
    subtitle: '代码片段、联系方式、常用模版',
    description: '通过斜杠指令（如 /email, /code, /address）瞬间展开常用长文本，支持动态计算时间与变量。',
    triggerKey: '输入 / 指令',
    exampleOriginal: '/code-react',
    exampleProcessed: 'export default function Component() { return <div className="p-4">...</div>; }',
    tag: '高效模版'
  },
  {
    id: 'ecosystem-flow',
    iconName: 'Workflow',
    title: 'GSYEN 生态联动',
    subtitle: '打字直达 GSYEN 工作区命令',
    description: '与 GSYEN 笔记、GSYEN 终端无缝对接。输入控制指令或触发快捷搜寻，打字即是操作。',
    triggerKey: 'Ctrl + Shift + G',
    exampleOriginal: '> 创建 GSYEN 任务卡片：更新官网域名 DNS',
    exampleProcessed: '已在 GSYEN Workspace 中创建待办事项，并关联至今日日志。',
    tag: '生态集成'
  }
];

export const ECOSYSTEM_MODULES: EcosystemModule[] = [
  {
    id: 'workspace',
    name: 'GSYEN Workspace',
    category: '智能协同工作台',
    description: '集知识管理、项目看板与本地文档库于一体的模块化生产力套件。',
    accentColor: 'from-blue-600 to-indigo-600',
    status: '无缝对接'
  },
  {
    id: 'notes',
    name: 'GSYEN Notes',
    category: '本地优先极简笔记',
    description: '支持 Markdown 与块级编辑，GY输入法可实现原位智能大纲生成与双向链接。',
    accentColor: 'from-sky-500 to-blue-700',
    status: '原生深度融合'
  },
  {
    id: 'terminal',
    name: 'GSYEN Terminal',
    category: '开发者命令行工具',
    description: '为 Windows 命令行提供自然语言转 Shell 命令、语法高亮与智能提示补全。',
    accentColor: 'from-slate-700 to-slate-900',
    status: '开发者预览'
  },
  {
    id: 'canvas',
    name: 'GSYEN Canvas',
    category: '无限白板与脑图',
    description: '思维导图与流向图创作工具，打字节点自动排版与关联分析。',
    accentColor: 'from-blue-500 to-teal-600',
    status: '已集成'
  }
];

export const CHANGELOG_HISTORY: VersionInfo[] = [
  {
    version: 'v1.2.0-preview',
    date: '2026-07-28',
    channel: '早期预览版 (Preview)',
    size: '32.4 MB',
    architecture: 'x64 / ARM64',
    sha256: 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
    highlights: [
      '新增：基础输入核心引擎 C++ 2.0 重构，出词延迟缩短至 0.8ms 内',
      '新增：全新微光质感候选框设计，适配 Windows 11 Fluent 视觉语言与圆角',
      '新增：智能上下文拼音纠错引擎，大幅降低长句误打率',
      '优化：AI 改写功能响应速度，支持快捷键 Alt+/ 原位触发与撤销',
      '隐私：新增透明网络日志审计台，随时查看所有数据进出记录'
    ]
  },
  {
    version: 'v1.1.2-beta',
    date: '2026-06-15',
    channel: 'Beta 测试版',
    size: '30.1 MB',
    architecture: 'x64',
    sha256: 'a1f8c921345d81249afbf4c8996fb92427ae41e4649b934ca495991b7852b999',
    highlights: [
      '新增：双拼方案自定义导入导出功能',
      '新增：剪贴板历史记录本地加密存储与快捷搜索',
      '修复：在某些 Windows 10 全屏游戏下的候选框显示层级问题'
    ]
  }
];
