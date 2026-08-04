import React, { useState } from 'react';
import {
  Sliders,
  Keyboard,
  HardDrive,
  Sparkles,
  ShieldCheck,
  Lock,
  Palette,
  Info,
  Search,
  Check,
  RefreshCw,
  ExternalLink,
  Download,
  Upload,
  Trash2,
  X,
  Moon,
  Sun,
  Monitor
} from 'lucide-react';
import { UserSettings, ThemeMode, InputMode, PinyinType, AiTriggerMode } from '../types';
import { GYBrandLogo } from './GYBrandLogo';

interface SettingsLayoutProps {
  settings: UserSettings;
  activeTab?: string;
  onClose: () => void;
  onUpdateSettings: (updater: (prev: UserSettings) => UserSettings) => void;
  onCheckUpdate: () => void;
}

export const SettingsLayout: React.FC<SettingsLayoutProps> = ({
  settings,
  activeTab = 'general',
  onClose,
  onUpdateSettings,
  onCheckUpdate,
}) => {
  const [currentTab, setCurrentTab] = useState(activeTab);
  const [searchQuery, setSearchQuery] = useState('');
  const [showClearToast, setShowClearToast] = useState(false);

  const isDark = settings.appearance.theme === 'dark';

  const navItems = [
    { id: 'general', label: '常规', icon: Sliders },
    { id: 'input', label: '输入', icon: Keyboard },
    { id: 'lexicon', label: '词库与学习', icon: HardDrive },
    { id: 'ai', label: 'AI 辅助', icon: Sparkles },
    { id: 'privacy', label: '隐私', icon: ShieldCheck },
    { id: 'security', label: '安全', icon: Lock },
    { id: 'appearance', label: '外观', icon: Palette },
    { id: 'about', label: '关于', icon: Info },
  ];

  const filteredNavItems = navItems.filter((item) =>
    item.label.toLowerCase().includes(searchQuery.toLowerCase())
  );

  return (
    <div className="fixed inset-0 bg-black/40 backdrop-blur-xs z-50 flex items-center justify-center p-4 animate-in fade-in duration-200">
      <div
        className={`
          w-full max-w-5xl h-[680px] rounded-2xl shadow-2xl border flex overflow-hidden
          ${
            isDark
              ? 'bg-slate-900 border-slate-700/80 text-slate-100 shadow-slate-950/90'
              : 'bg-white border-slate-200/90 text-slate-800 shadow-slate-400/30'
          }
        `}
      >
        {/* Left Sidebar Navigation */}
        <div
          className={`w-60 shrink-0 border-r p-4 flex flex-col justify-between ${
            isDark ? 'border-slate-800 bg-slate-950/70' : 'border-slate-100 bg-slate-50/80'
          }`}
        >
          <div className="space-y-4">
            {/* Header Brand */}
            <div className="flex items-center gap-3 px-2 py-1">
              <div className="w-11 h-8 flex items-center justify-center" title="GY 输入法">
                <GYBrandLogo height={25} color={isDark ? '#F8FAFC' : '#111318'} />
              </div>
              <div>
                <div className="font-bold text-sm tracking-tight">{settings.about.appName}</div>
                <div className="text-[11px] text-slate-400 font-mono">设置中心 v{settings.about.version}</div>
              </div>
            </div>

            {/* Search Input */}
            <div className="relative">
              <Search className="w-3.5 h-3.5 text-slate-400 absolute left-3 top-2.5" />
              <input
                type="text"
                placeholder="搜索设置项..."
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                className={`w-full pl-8 pr-3 py-1.5 text-xs rounded-lg border outline-none ${
                  isDark
                    ? 'bg-slate-900 border-slate-800 text-slate-200 focus:border-blue-500'
                    : 'bg-white border-slate-200 text-slate-700 focus:border-blue-500'
                }`}
              />
            </div>

            {/* Navigation List */}
            <nav className="space-y-1">
              {filteredNavItems.map((item) => {
                const Icon = item.icon;
                const isActive = currentTab === item.id;
                return (
                  <button
                    key={item.id}
                    onClick={() => setCurrentTab(item.id)}
                    className={`
                      w-full flex items-center gap-2.5 px-3 py-2 rounded-xl text-xs font-medium transition-all text-left
                      ${
                        isActive
                          ? 'bg-blue-600 text-white shadow-md font-semibold'
                          : isDark
                          ? 'text-slate-300 hover:bg-slate-800/80'
                          : 'text-slate-600 hover:bg-slate-200/60'
                      }
                    `}
                  >
                    <Icon className="w-4 h-4" />
                    <span>{item.label}</span>
                  </button>
                );
              })}
            </nav>
          </div>

          {/* Sidebar Footer */}
          <div className="pt-3 border-t border-slate-200 dark:border-slate-800 text-[11px] text-slate-400 flex items-center justify-between px-2">
            <span>母品牌 {settings.about.brand}</span>
            <span className="text-emerald-600 dark:text-emerald-400 font-mono">100% 本地优先</span>
          </div>
        </div>

        {/* Right Main Content Area */}
        <div className="flex-1 flex flex-col justify-between overflow-hidden">
          {/* Top Window Bar */}
          <div
            className={`px-8 py-4 border-b flex items-center justify-between ${
              isDark ? 'border-slate-800 bg-slate-900/50' : 'border-slate-100 bg-white'
            }`}
          >
            <div className="text-lg font-bold">
              {navItems.find((n) => n.id === currentTab)?.label || '设置'}
            </div>

            <button
              onClick={onClose}
              className={`p-1.5 rounded-xl transition-colors ${
                isDark ? 'hover:bg-slate-800 text-slate-400' : 'hover:bg-slate-100 text-slate-500'
              }`}
            >
              <X className="w-5 h-5" />
            </button>
          </div>

          {/* Content Pane */}
          <div className="flex-1 overflow-y-auto p-8 space-y-6">
            {/* 1. 常规设置 (General) */}
            {currentTab === 'general' && (
              <div className="space-y-6 max-w-2xl">
                <div className="space-y-4">
                  <h3 className="text-sm font-semibold text-slate-500 dark:text-slate-400 uppercase tracking-wider">
                    基础习惯
                  </h3>

                  <div className={`p-4 rounded-xl border space-y-4 ${isDark ? 'border-slate-800 bg-slate-950/40' : 'border-slate-200 bg-slate-50/50'}`}>
                    <div className="flex items-center justify-between">
                      <div>
                        <div className="font-medium text-sm">开机自动启动</div>
                        <div className="text-xs text-slate-400">Windows 登录后自动在后台装载 GY输入法</div>
                      </div>
                      <input
                        type="checkbox"
                        checked={settings.general.startOnBoot}
                        onChange={(e) =>
                          onUpdateSettings((prev) => ({
                            ...prev,
                            general: { ...prev.general, startOnBoot: e.target.checked },
                          }))
                        }
                        className="w-5 h-5 rounded text-blue-600 focus:ring-blue-500 border-slate-300"
                      />
                    </div>

                    <div className="border-t border-slate-200/60 dark:border-slate-800" />

                    <div className="flex items-center justify-between">
                      <div>
                        <div className="font-medium text-sm">默认中英文状态</div>
                        <div className="text-xs text-slate-400">切换到新应用时的初始输入模式</div>
                      </div>
                      <select
                        value={settings.general.defaultLanguage}
                        onChange={(e) =>
                          onUpdateSettings((prev) => ({
                            ...prev,
                            general: { ...prev.general, defaultLanguage: e.target.value as InputMode },
                          }))
                        }
                        className={`text-xs px-3 py-1.5 rounded-lg border outline-none ${
                          isDark ? 'bg-slate-800 border-slate-700' : 'bg-white border-slate-300'
                        }`}
                      >
                        <option value="zh">默认中文输入</option>
                        <option value="en">默认英文模式</option>
                      </select>
                    </div>

                    <div className="border-t border-slate-200/60 dark:border-slate-800" />

                    <div className="flex items-center justify-between">
                      <div>
                        <div className="font-medium text-sm">中英文切换快捷键</div>
                        <div className="text-xs text-slate-400">单击快捷键快速切换中英输入</div>
                      </div>
                      <select
                        value={settings.general.shortcutToggle}
                        onChange={(e) =>
                          onUpdateSettings((prev) => ({
                            ...prev,
                            general: { ...prev.general, shortcutToggle: e.target.value },
                          }))
                        }
                        className={`text-xs px-3 py-1.5 rounded-lg border outline-none ${
                          isDark ? 'bg-slate-800 border-slate-700' : 'bg-white border-slate-300'
                        }`}
                      >
                        <option value="Shift">左 / 右 Shift 键</option>
                        <option value="Ctrl">Ctrl 键</option>
                        <option value="Ctrl+Space">Ctrl + 空格</option>
                      </select>
                    </div>
                  </div>
                </div>
              </div>
            )}

            {/* 2. 输入设置 (Input) */}
            {currentTab === 'input' && (
              <div className="space-y-6 max-w-2xl">
                <div className="space-y-4">
                  <h3 className="text-sm font-semibold text-slate-500 dark:text-slate-400 uppercase tracking-wider">
                    拼音与候选习惯
                  </h3>

                  <div className={`p-4 rounded-xl border space-y-4 ${isDark ? 'border-slate-800 bg-slate-950/40' : 'border-slate-200 bg-slate-50/50'}`}>
                    <div className="flex items-center justify-between">
                      <div>
                        <div className="font-medium text-sm">拼音方案</div>
                        <div className="text-xs text-slate-400">全拼或各种双拼编码</div>
                      </div>
                      <select
                        value={settings.input.pinyinType}
                        onChange={(e) =>
                          onUpdateSettings((prev) => ({
                            ...prev,
                            input: { ...prev.input, pinyinType: e.target.value as PinyinType },
                          }))
                        }
                        className={`text-xs px-3 py-1.5 rounded-lg border outline-none ${
                          isDark ? 'bg-slate-800 border-slate-700' : 'bg-white border-slate-300'
                        }`}
                      >
                        <option value="quanpin">全拼 (标准全拼)</option>
                        <option value="shuangpin">微软双拼</option>
                      </select>
                    </div>

                    <div className="border-t border-slate-200/60 dark:border-slate-800" />

                    <div className="flex items-center justify-between">
                      <div>
                        <div className="font-medium text-sm">模糊音识别</div>
                        <div className="text-xs text-slate-400">自动纠正平仄音、前后鼻音与平舌音</div>
                      </div>
                      <input
                        type="checkbox"
                        checked={settings.input.fuzzyPinyin}
                        onChange={(e) =>
                          onUpdateSettings((prev) => ({
                            ...prev,
                            input: { ...prev.input, fuzzyPinyin: e.target.checked },
                          }))
                        }
                        className="w-5 h-5 rounded text-blue-600 focus:ring-blue-500 border-slate-300"
                      />
                    </div>

                    <div className="border-t border-slate-200/60 dark:border-slate-800" />

                    <div className="flex items-center justify-between">
                      <div>
                        <div className="font-medium text-sm">候选词展示数量 ({settings.input.candidateCount} 个)</div>
                        <div className="text-xs text-slate-400">首屏单行横向展示的候选数量 (5 - 9)</div>
                      </div>
                      <input
                        type="range"
                        min="5"
                        max="9"
                        value={settings.input.candidateCount}
                        onChange={(e) =>
                          onUpdateSettings((prev) => ({
                            ...prev,
                            input: { ...prev.input, candidateCount: parseInt(e.target.value) },
                          }))
                        }
                        className="w-32 accent-blue-600"
                      />
                    </div>

                    <div className="border-t border-slate-200/60 dark:border-slate-800" />

                    <div className="flex items-center justify-between">
                      <div>
                        <div className="font-medium text-sm">候选窗字号大小 ({settings.input.candidateFontSize} px)</div>
                        <div className="text-xs text-slate-400">提升高分屏下的文字清晰度</div>
                      </div>
                      <input
                        type="range"
                        min="14"
                        max="22"
                        value={settings.input.candidateFontSize}
                        onChange={(e) =>
                          onUpdateSettings((prev) => ({
                            ...prev,
                            input: { ...prev.input, candidateFontSize: parseInt(e.target.value) },
                            appearance: { ...prev.appearance, candidateFontSize: parseInt(e.target.value) },
                          }))
                        }
                        className="w-32 accent-blue-600"
                      />
                    </div>
                  </div>
                </div>
              </div>
            )}

            {/* 3. 词库与学习 (Lexicon & Learning) */}
            {currentTab === 'lexicon' && (
              <div className="space-y-6 max-w-2xl">
                <div className="space-y-4">
                  <h3 className="text-sm font-semibold text-slate-500 dark:text-slate-400 uppercase tracking-wider">
                    个人词库与记忆引擎
                  </h3>

                  <div className={`p-4 rounded-xl border space-y-4 ${isDark ? 'border-slate-800 bg-slate-950/40' : 'border-slate-200 bg-slate-50/50'}`}>
                    <div className="flex items-center justify-between">
                      <div>
                        <div className="font-medium text-sm">本地词频调整与自动学习</div>
                        <div className="text-xs text-slate-400">根据打字习惯自动优化首选词顺，数据完全存在本机</div>
                      </div>
                      <input
                        type="checkbox"
                        checked={settings.lexicon.localLearning}
                        onChange={(e) =>
                          onUpdateSettings((prev) => ({
                            ...prev,
                            lexicon: { ...prev.lexicon, localLearning: e.target.checked },
                          }))
                        }
                        className="w-5 h-5 rounded text-blue-600 focus:ring-blue-500 border-slate-300"
                      />
                    </div>

                    <div className="border-t border-slate-200/60 dark:border-slate-800" />

                    <div className="flex items-center justify-between">
                      <div>
                        <div className="font-medium text-sm">已积累个人词频总计</div>
                        <div className="text-xs text-emerald-600 dark:text-emerald-400 font-mono">
                          {settings.lexicon.userWordsCount.toLocaleString()} 条个人自造词与频次记录
                        </div>
                      </div>
                      <div className="flex items-center gap-2">
                        <button
                          onClick={() => {
                            alert('已导出本地词库 JSON 备份文件 gy_lexicon_backup.json');
                          }}
                          className="px-3 py-1.5 rounded-lg border text-xs font-medium hover:bg-slate-100 dark:hover:bg-slate-800 flex items-center gap-1"
                        >
                          <Download className="w-3.5 h-3.5" /> 导出词库
                        </button>
                        <button
                          onClick={() => {
                            alert('支持 txt / dict 标准格式词库导入');
                          }}
                          className="px-3 py-1.5 rounded-lg border text-xs font-medium hover:bg-slate-100 dark:hover:bg-slate-800 flex items-center gap-1"
                        >
                          <Upload className="w-3.5 h-3.5" /> 导入词库
                        </button>
                      </div>
                    </div>

                    <div className="border-t border-slate-200/60 dark:border-slate-800" />

                    <div className="flex items-center justify-between">
                      <div>
                        <div className="font-medium text-sm text-red-600 dark:text-red-400">清除个人打字记忆</div>
                        <div className="text-xs text-slate-400">彻底清空本地学习的自造词与个人频次统计</div>
                      </div>
                      <button
                        onClick={() => {
                          if (confirm('确认清除本地所有自造词频次记录？此操作不可撤销。')) {
                            onUpdateSettings((prev) => ({
                              ...prev,
                              lexicon: { ...prev.lexicon, userWordsCount: 0 },
                            }));
                            setShowClearToast(true);
                            setTimeout(() => setShowClearToast(false), 3000);
                          }
                        }}
                        className="px-3 py-1.5 rounded-lg bg-red-500/10 hover:bg-red-500/20 text-red-600 dark:text-red-400 border border-red-200 dark:border-red-900 text-xs font-medium flex items-center gap-1"
                      >
                        <Trash2 className="w-3.5 h-3.5" /> 清除词频
                      </button>
                    </div>
                  </div>
                </div>
              </div>
            )}

            {/* 4. AI 辅助设置 (AI Assistant) */}
            {currentTab === 'ai' && (
              <div className="space-y-6 max-w-2xl">
                <div className="space-y-4">
                  <h3 className="text-sm font-semibold text-slate-500 dark:text-slate-400 uppercase tracking-wider">
                    AI 辅助交互与策略
                  </h3>

                  <div className={`p-4 rounded-xl border space-y-4 ${isDark ? 'border-slate-800 bg-slate-950/40' : 'border-slate-200 bg-slate-50/50'}`}>
                    <div className="flex items-center justify-between">
                      <div>
                        <div className="font-medium text-sm">AI 辅助功能总开关</div>
                        <div className="text-xs text-slate-400">关闭后，所有快捷键与 AI 按钮均处于完全停用状态</div>
                      </div>
                      <input
                        type="checkbox"
                        checked={settings.ai.aiMasterToggle}
                        onChange={(e) =>
                          onUpdateSettings((prev) => ({
                            ...prev,
                            ai: {
                              ...prev.ai,
                              aiMasterToggle: e.target.checked,
                              aiTriggerMode: e.target.checked ? 'manual' : 'off',
                            },
                          }))
                        }
                        className="w-5 h-5 rounded text-blue-600 focus:ring-blue-500 border-slate-300"
                      />
                    </div>

                    <div className="border-t border-slate-200/60 dark:border-slate-800" />

                    <div className="flex items-center justify-between">
                      <div>
                        <div className="font-medium text-sm">唤醒触发模式</div>
                        <div className="text-xs text-slate-400">严格遵守“仅在用户主动触发时出现”</div>
                      </div>
                      <select
                        value={settings.ai.aiTriggerMode}
                        onChange={(e) =>
                          onUpdateSettings((prev) => ({
                            ...prev,
                            ai: { ...prev.ai, aiTriggerMode: e.target.value as AiTriggerMode },
                          }))
                        }
                        className={`text-xs px-3 py-1.5 rounded-lg border outline-none ${
                          isDark ? 'bg-slate-800 border-slate-700' : 'bg-white border-slate-300'
                        }`}
                      >
                        <option value="manual">仅手动触发 (推荐)</option>
                        <option value="off">完全关闭</option>
                        <option value="on">主动唤醒提示</option>
                      </select>
                    </div>

                    <div className="border-t border-slate-200/60 dark:border-slate-800" />

                    <div className="flex items-center justify-between">
                      <div>
                        <div className="font-medium text-sm">唤醒面板快捷键</div>
                        <div className="text-xs text-slate-400">选中任意文本按下快捷键弹出 AI 助手</div>
                      </div>
                      <span className="font-mono text-xs px-2.5 py-1 rounded bg-slate-200 dark:bg-slate-800 border font-medium">
                        {settings.ai.aiShortcuts}
                      </span>
                    </div>

                    <div className="border-t border-slate-200/60 dark:border-slate-800" />

                    <div className="p-3 rounded-lg bg-blue-500/10 text-blue-800 dark:text-blue-300 text-xs leading-relaxed border border-blue-200 dark:border-blue-900">
                      <strong>数据处理声明：</strong> GY输入法 AI 助手仅在您主动按下快捷键或点击面板按钮后，将您指定框选的文案发送至 AI 模型进行润色或翻译。输入法后台绝无幕后抓取或隐秘分析打字流的行为。
                    </div>
                  </div>
                </div>
              </div>
            )}

            {/* 5. 隐私设置 (Privacy) */}
            {currentTab === 'privacy' && (
              <div className="space-y-6 max-w-2xl">
                <div className="space-y-4">
                  <h3 className="text-sm font-semibold text-slate-500 dark:text-slate-400 uppercase tracking-wider">
                    本地优先 & 隐私承诺
                  </h3>

                  <div className={`p-5 rounded-2xl border space-y-4 ${isDark ? 'border-emerald-800/60 bg-emerald-950/20' : 'border-emerald-200 bg-emerald-50/40'}`}>
                    <div className="flex items-start gap-3">
                      <ShieldCheck className="w-6 h-6 text-emerald-600 dark:text-emerald-400 shrink-0 mt-0.5" />
                      <div className="space-y-2">
                        <div className="font-bold text-base text-emerald-900 dark:text-emerald-200">
                          GY输入法 隐私本地第一法则
                        </div>
                        <ul className="text-xs text-emerald-800 dark:text-emerald-300 space-y-2 list-disc pl-4 leading-relaxed">
                          <li><strong>基础打字与词频逻辑 100% 在本机处理</strong>，无需建立云端账户即可享受极致输入速度。</li>
                          <li><strong>AI 请求只在主动触发后发送</strong>，绝不常驻后台窃听、分析或窥探用户键盘输入。</li>
                          <li><strong>透明自治</strong>：用户可随时一键导出、查阅或永久销毁本地存储的自造词频与历史字典。</li>
                        </ul>
                      </div>
                    </div>
                  </div>

                  <div className={`p-4 rounded-xl border space-y-4 ${isDark ? 'border-slate-800 bg-slate-950/40' : 'border-slate-200 bg-slate-50/50'}`}>
                    <div className="flex items-center justify-between">
                      <div>
                        <div className="font-medium text-sm">键盘数据内存加密</div>
                        <div className="text-xs text-slate-400">对运行内存中的拼音预编辑流采用 AES-256 临时加密</div>
                      </div>
                      <input
                        type="checkbox"
                        checked={settings.privacy.memoryEncryption}
                        onChange={(e) =>
                          onUpdateSettings((prev) => ({
                            ...prev,
                            privacy: { ...prev.privacy, memoryEncryption: e.target.checked },
                          }))
                        }
                        className="w-5 h-5 rounded text-blue-600 focus:ring-blue-500 border-slate-300"
                      />
                    </div>
                  </div>
                </div>
              </div>
            )}

            {/* 6. 安全设置 (Security) */}
            {currentTab === 'security' && (
              <div className="space-y-6 max-w-2xl">
                <div className="space-y-4">
                  <h3 className="text-sm font-semibold text-slate-500 dark:text-slate-400 uppercase tracking-wider">
                    代码可信与隔离防护
                  </h3>

                  <div className={`p-4 rounded-xl border space-y-4 ${isDark ? 'border-slate-800 bg-slate-950/40' : 'border-slate-200 bg-slate-50/50'}`}>
                    <div className="flex items-center justify-between">
                      <div>
                        <div className="font-medium text-sm flex items-center gap-1.5">
                          <span>GSYEN 官方数字签名认证</span>
                          <span className="text-[10px] px-2 py-0.5 rounded bg-emerald-500/10 text-emerald-600 font-mono">
                            VERIFIED
                          </span>
                        </div>
                        <div className="text-xs text-slate-400">已通过 Windows SmartScreen 与 EV 二进制证书防篡改校验</div>
                      </div>
                      <Check className="w-5 h-5 text-emerald-500" />
                    </div>

                    <div className="border-t border-slate-200/60 dark:border-slate-800" />

                    <div className="flex items-center justify-between">
                      <div>
                        <div className="font-medium text-sm">网络白名单管制</div>
                        <div className="text-xs text-slate-400">限制主进程仅访问必要的白名单域名（shurufa.wang）</div>
                      </div>
                      <input
                        type="checkbox"
                        checked={settings.security.offlineWhitelist}
                        onChange={(e) =>
                          onUpdateSettings((prev) => ({
                            ...prev,
                            security: { ...prev.security, offlineWhitelist: e.target.checked },
                          }))
                        }
                        className="w-5 h-5 rounded text-blue-600 focus:ring-blue-500 border-slate-300"
                      />
                    </div>
                  </div>
                </div>
              </div>
            )}

            {/* 7. 外观设置 (Appearance) */}
            {currentTab === 'appearance' && (
              <div className="space-y-6 max-w-2xl">
                <div className="space-y-4">
                  <h3 className="text-sm font-semibold text-slate-500 dark:text-slate-400 uppercase tracking-wider">
                    视觉与主题样式
                  </h3>

                  <div className={`p-4 rounded-xl border space-y-4 ${isDark ? 'border-slate-800 bg-slate-950/40' : 'border-slate-200 bg-slate-50/50'}`}>
                    <div className="space-y-2">
                      <div className="font-medium text-sm">颜色主题模式</div>
                      <div className="grid grid-cols-3 gap-3">
                        <button
                          onClick={() =>
                            onUpdateSettings((prev) => ({
                              ...prev,
                              appearance: { ...prev.appearance, theme: 'light' },
                            }))
                          }
                          className={`p-3 rounded-xl border flex flex-col items-center gap-2 transition-all ${
                            settings.appearance.theme === 'light'
                              ? 'border-blue-600 bg-blue-50/50 dark:bg-blue-950/40 text-blue-700 dark:text-blue-300 font-semibold'
                              : 'border-slate-200 dark:border-slate-800 text-slate-600 dark:text-slate-400'
                          }`}
                        >
                          <Sun className="w-5 h-5" />
                          <span className="text-xs">浅色模式 (暖白)</span>
                        </button>

                        <button
                          onClick={() =>
                            onUpdateSettings((prev) => ({
                              ...prev,
                              appearance: { ...prev.appearance, theme: 'dark' },
                            }))
                          }
                          className={`p-3 rounded-xl border flex flex-col items-center gap-2 transition-all ${
                            settings.appearance.theme === 'dark'
                              ? 'border-blue-600 bg-blue-950/80 text-blue-300 font-semibold'
                              : 'border-slate-200 dark:border-slate-800 text-slate-600 dark:text-slate-400'
                          }`}
                        >
                          <Moon className="w-5 h-5" />
                          <span className="text-xs">深色模式</span>
                        </button>

                        <button
                          onClick={() =>
                            onUpdateSettings((prev) => ({
                              ...prev,
                              appearance: { ...prev.appearance, theme: 'system' },
                            }))
                          }
                          className={`p-3 rounded-xl border flex flex-col items-center gap-2 transition-all ${
                            settings.appearance.theme === 'system'
                              ? 'border-blue-600 bg-blue-50/50 dark:bg-blue-950/40 text-blue-700 dark:text-blue-300 font-semibold'
                              : 'border-slate-200 dark:border-slate-800 text-slate-600 dark:text-slate-400'
                          }`}
                        >
                          <Monitor className="w-5 h-5" />
                          <span className="text-xs">跟随系统</span>
                        </button>
                      </div>
                    </div>

                    <div className="border-t border-slate-200/60 dark:border-slate-800" />

                    <div className="flex items-center justify-between">
                      <div>
                        <div className="font-medium text-sm">候选窗透明度 ({settings.appearance.candidateOpacity}%)</div>
                        <div className="text-xs text-slate-400">控制磨砂玻璃效果的透光度</div>
                      </div>
                      <input
                        type="range"
                        min="70"
                        max="100"
                        value={settings.appearance.candidateOpacity}
                        onChange={(e) =>
                          onUpdateSettings((prev) => ({
                            ...prev,
                            appearance: { ...prev.appearance, candidateOpacity: parseInt(e.target.value) },
                          }))
                        }
                        className="w-32 accent-blue-600"
                      />
                    </div>

                    <div className="border-t border-slate-200/60 dark:border-slate-800" />

                    <div className="flex items-center justify-between">
                      <div>
                        <div className="font-medium text-sm">候选窗圆角半径 ({settings.appearance.cornerRadius} px)</div>
                        <div className="text-xs text-slate-400">标准 Windows 11 Fluent 风格 10px</div>
                      </div>
                      <input
                        type="range"
                        min="6"
                        max="16"
                        value={settings.appearance.cornerRadius}
                        onChange={(e) =>
                          onUpdateSettings((prev) => ({
                            ...prev,
                            appearance: { ...prev.appearance, cornerRadius: parseInt(e.target.value) },
                          }))
                        }
                        className="w-32 accent-blue-600"
                      />
                    </div>
                  </div>
                </div>
              </div>
            )}

            {/* 8. 关于 (About) */}
            {currentTab === 'about' && (
              <div className="space-y-6 max-w-2xl">
                <div className={`p-6 rounded-2xl border flex flex-col items-center text-center space-y-4 ${
                  isDark ? 'border-slate-800 bg-slate-950/40' : 'border-slate-200 bg-slate-50/50'
                }`}>
                  <div className="h-16 flex items-center justify-center" title="GY 输入法">
                    <GYBrandLogo height={50} color={isDark ? '#F8FAFC' : '#111318'} />
                  </div>

                  <div>
                    <h2 className="text-xl font-bold">{settings.about.appName}</h2>
                    <p className="text-xs text-slate-400 font-mono mt-0.5">
                      {settings.about.englishName} • Version {settings.about.version} ({settings.about.buildNumber})
                    </p>
                  </div>

                  <p className="text-xs text-slate-500 dark:text-slate-400 max-w-md leading-relaxed">
                    GY输入法是 GSYEN 旗下专为 Windows 平台打造的精细中文输入系统。坚持快、准、本地优先的理念，AI 仅在您主动触发时启动。
                  </p>

                  <div className="flex items-center gap-3 pt-2">
                    <button
                      onClick={onCheckUpdate}
                      className="px-4 py-2 rounded-xl bg-blue-600 hover:bg-blue-700 text-white font-medium text-xs shadow-md transition-all flex items-center gap-1.5"
                    >
                      <RefreshCw className="w-3.5 h-3.5" />
                      <span>检查版本更新</span>
                    </button>

                    <a
                      href={`https://${settings.about.website}`}
                      target="_blank"
                      rel="noopener noreferrer"
                      className="px-4 py-2 rounded-xl border hover:bg-slate-100 dark:hover:bg-slate-800 font-medium text-xs transition-colors flex items-center gap-1.5"
                    >
                      <span>官网 {settings.about.website}</span>
                      <ExternalLink className="w-3.5 h-3.5" />
                    </a>
                  </div>
                </div>

                <div className="text-center text-[11px] text-slate-400 space-y-1">
                  <p>© 2026 GSYEN. All rights reserved.</p>
                  <p>Microsoft YaHei UI / Segoe UI Font Rendering Engine Supported</p>
                </div>
              </div>
            )}
          </div>

          {/* Toast Notice */}
          {showClearToast && (
            <div className="mx-8 mb-4 p-3 rounded-xl bg-emerald-500/10 border border-emerald-500/30 text-emerald-600 dark:text-emerald-400 text-xs font-medium flex items-center justify-between animate-in fade-in">
              <div className="flex items-center gap-2">
                <Check className="w-4 h-4" />
                <span>已重置本地所有自造词频！</span>
              </div>
            </div>
          )}

          {/* Bottom Bar */}
          <div
            className={`px-8 py-4 border-t flex items-center justify-between text-xs ${
              isDark ? 'border-slate-800 bg-slate-950/80' : 'border-slate-100 bg-slate-50'
            }`}
          >
            <span className="text-slate-400">更改设置后自动实时生效与保存</span>

            <button
              onClick={onClose}
              className="px-5 py-2 rounded-xl bg-blue-600 hover:bg-blue-700 text-white font-medium transition-all shadow-md"
            >
              完成并保存
            </button>
          </div>
        </div>
      </div>
    </div>
  );
};
