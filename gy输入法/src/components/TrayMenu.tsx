import React, { useState } from 'react';
import {
  Globe,
  Sliders,
  Sparkles,
  RefreshCw,
  Power,
  Check,
  ShieldCheck,
  Cpu,
  Keyboard,
  Moon,
  Sun,
  X,
  ExternalLink
} from 'lucide-react';
import { UserSettings, InputMode, PinyinType, AiTriggerMode } from '../types';
import { GYBrandLogo } from './GYBrandLogo';

interface TrayMenuProps {
  settings: UserSettings;
  isOpen: boolean;
  onClose: () => void;
  onOpenSettings: (tab?: string) => void;
  onUpdateSettings: (updater: (prev: UserSettings) => UserSettings) => void;
  onCheckUpdate: () => void;
  onToggleTheme: () => void;
}

export const TrayMenu: React.FC<TrayMenuProps> = ({
  settings,
  isOpen,
  onClose,
  onOpenSettings,
  onUpdateSettings,
  onCheckUpdate,
  onToggleTheme,
}) => {
  if (!isOpen) return null;

  const isDark = settings.appearance.theme === 'dark';

  const handleSetLanguage = (mode: InputMode) => {
    onUpdateSettings((prev) => ({
      ...prev,
      general: { ...prev.general, defaultLanguage: mode },
    }));
  };

  const handleSetPinyinType = (type: PinyinType) => {
    onUpdateSettings((prev) => ({
      ...prev,
      input: { ...prev.input, pinyinType: type },
    }));
  };

  const handleSetAiTrigger = (mode: AiTriggerMode) => {
    onUpdateSettings((prev) => ({
      ...prev,
      ai: { ...prev.ai, aiTriggerMode: mode, aiMasterToggle: mode !== 'off' },
    }));
  };

  return (
    <div
      id="tray-popover-menu"
      className={`
        fixed bottom-12 right-6 w-80 rounded-xl shadow-2xl border z-50 overflow-hidden
        backdrop-blur-xl transition-all duration-200 animate-in fade-in slide-in-from-bottom-2
        ${
          isDark
            ? 'bg-slate-900/95 border-slate-700/80 text-slate-100 shadow-slate-950/80'
            : 'bg-white/95 border-slate-200/90 text-slate-800 shadow-slate-400/30'
        }
      `}
    >
      {/* Header Banner */}
      <div
        className={`px-4 py-3 border-b flex items-center justify-between ${
          isDark ? 'border-slate-800 bg-slate-950/60' : 'border-slate-100 bg-slate-50/80'
        }`}
      >
        <div className="flex items-center gap-2.5">
          <div className="w-11 h-8 flex items-center justify-center" title="GY 输入法">
            <GYBrandLogo height={25} color={isDark ? '#F8FAFC' : '#111318'} />
          </div>
          <div>
            <div className="flex items-center gap-1.5 font-semibold text-sm">
              <span>{settings.about.appName}</span>
              <span className="text-[10px] px-1.5 py-0.2 rounded bg-blue-100 dark:bg-blue-950 text-blue-700 dark:text-blue-300 font-mono">
                v{settings.about.version}
              </span>
            </div>
            <div className="text-[11px] text-slate-500 dark:text-slate-400 flex items-center gap-1">
              <span>母品牌：{settings.about.brand}</span>
              <span>•</span>
              <span className="text-emerald-600 dark:text-emerald-400 flex items-center gap-0.5">
                <ShieldCheck className="w-3 h-3" /> 本地模式
              </span>
            </div>
          </div>
        </div>

        <button
          onClick={onClose}
          className={`p-1 rounded-lg transition-colors ${
            isDark ? 'hover:bg-slate-800 text-slate-400' : 'hover:bg-slate-200/80 text-slate-500'
          }`}
        >
          <X className="w-4 h-4" />
        </button>
      </div>

      {/* Main Controls List */}
      <div className="p-3 space-y-3 text-xs">
        {/* Language Selection: 中文 / English */}
        <div className="space-y-1">
          <div className="text-[11px] font-medium text-slate-400 px-1 flex items-center justify-between">
            <span>输入语言</span>
            <span className="font-mono text-blue-600 dark:text-blue-400 font-semibold">
              {settings.general.defaultLanguage === 'zh' ? '中文 (zh)' : 'English (en)'}
            </span>
          </div>
          <div className="grid grid-cols-2 gap-1.5 p-1 rounded-lg bg-slate-100 dark:bg-slate-800/60">
            <button
              onClick={() => handleSetLanguage('zh')}
              className={`flex items-center justify-center gap-1.5 py-1.5 rounded-md font-medium transition-all ${
                settings.general.defaultLanguage === 'zh'
                  ? 'bg-white dark:bg-slate-700 text-blue-700 dark:text-blue-300 shadow-xs'
                  : 'text-slate-600 dark:text-slate-400 hover:text-slate-900 dark:hover:text-slate-200'
              }`}
            >
              <Globe className="w-3.5 h-3.5" />
              <span>中文</span>
            </button>
            <button
              onClick={() => handleSetLanguage('en')}
              className={`flex items-center justify-center gap-1.5 py-1.5 rounded-md font-medium transition-all ${
                settings.general.defaultLanguage === 'en'
                  ? 'bg-white dark:bg-slate-700 text-blue-700 dark:text-blue-300 shadow-xs'
                  : 'text-slate-600 dark:text-slate-400 hover:text-slate-900 dark:hover:text-slate-200'
              }`}
            >
              <Keyboard className="w-3.5 h-3.5" />
              <span>English</span>
            </button>
          </div>
        </div>

        {/* Pinyin Schema: 全拼 / 双拼 */}
        <div className="space-y-1">
          <div className="text-[11px] font-medium text-slate-400 px-1">拼音方案</div>
          <div className="grid grid-cols-2 gap-1.5 p-1 rounded-lg bg-slate-100 dark:bg-slate-800/60">
            <button
              onClick={() => handleSetPinyinType('quanpin')}
              className={`flex items-center justify-center gap-1.5 py-1.5 rounded-md font-medium transition-all ${
                settings.input.pinyinType === 'quanpin'
                  ? 'bg-white dark:bg-slate-700 text-blue-700 dark:text-blue-300 shadow-xs'
                  : 'text-slate-600 dark:text-slate-400'
              }`}
            >
              <span>全拼方案</span>
            </button>
            <button
              onClick={() => handleSetPinyinType('shuangpin')}
              className={`flex items-center justify-center gap-1.5 py-1.5 rounded-md font-medium transition-all ${
                settings.input.pinyinType === 'shuangpin'
                  ? 'bg-white dark:bg-slate-700 text-blue-700 dark:text-blue-300 shadow-xs'
                  : 'text-slate-600 dark:text-slate-400'
              }`}
            >
              <span>双拼方案</span>
            </button>
          </div>
        </div>

        {/* AI Assistant Mode: 关闭 / 仅手动触发 / 开启 */}
        <div className="space-y-1">
          <div className="text-[11px] font-medium text-slate-400 px-1 flex items-center justify-between">
            <span className="flex items-center gap-1">
              <Sparkles className="w-3.5 h-3.5 text-blue-600 dark:text-blue-400" />
              AI 辅助状态
            </span>
            <span className="text-[10px] text-emerald-600 dark:text-emerald-400 font-normal">主动触发</span>
          </div>

          <div className="grid grid-cols-3 gap-1 p-1 rounded-lg bg-slate-100 dark:bg-slate-800/60">
            <button
              onClick={() => handleSetAiTrigger('off')}
              className={`py-1.5 rounded-md font-medium text-center transition-all ${
                settings.ai.aiTriggerMode === 'off'
                  ? 'bg-white dark:bg-slate-700 text-slate-900 dark:text-slate-100 shadow-xs'
                  : 'text-slate-500 dark:text-slate-400'
              }`}
            >
              关闭
            </button>
            <button
              onClick={() => handleSetAiTrigger('manual')}
              className={`py-1.5 rounded-md font-medium text-center transition-all ${
                settings.ai.aiTriggerMode === 'manual'
                  ? 'bg-blue-600 text-white shadow-xs'
                  : 'text-slate-600 dark:text-slate-400'
              }`}
            >
              仅手动
            </button>
            <button
              onClick={() => handleSetAiTrigger('on')}
              className={`py-1.5 rounded-md font-medium text-center transition-all ${
                settings.ai.aiTriggerMode === 'on'
                  ? 'bg-white dark:bg-slate-700 text-blue-700 dark:text-blue-300 shadow-xs'
                  : 'text-slate-500 dark:text-slate-400'
              }`}
            >
              开启
            </button>
          </div>
        </div>

        <div className="border-t border-slate-200/60 dark:border-slate-800 my-2" />

        {/* Quick Menu Actions */}
        <div className="space-y-0.5">
          <button
            onClick={() => {
              onClose();
              onOpenSettings('general');
            }}
            className={`w-full flex items-center justify-between px-2.5 py-2 rounded-lg transition-colors ${
              isDark ? 'hover:bg-slate-800 text-slate-200' : 'hover:bg-slate-100 text-slate-700'
            }`}
          >
            <div className="flex items-center gap-2">
              <Sliders className="w-4 h-4 text-blue-600 dark:text-blue-400" />
              <span className="font-medium">打开设置中心</span>
            </div>
            <span className="text-[10px] text-slate-400 font-mono">Win + Shift + S</span>
          </button>

          <button
            onClick={onToggleTheme}
            className={`w-full flex items-center justify-between px-2.5 py-2 rounded-lg transition-colors ${
              isDark ? 'hover:bg-slate-800 text-slate-200' : 'hover:bg-slate-100 text-slate-700'
            }`}
          >
            <div className="flex items-center gap-2">
              {isDark ? <Sun className="w-4 h-4 text-amber-400" /> : <Moon className="w-4 h-4 text-slate-600" />}
              <span className="font-medium">切换界面主题</span>
            </div>
            <span className="text-[11px] text-slate-400 font-mono">
              {isDark ? '深色模式' : '浅色模式'}
            </span>
          </button>

          <button
            onClick={onCheckUpdate}
            className={`w-full flex items-center justify-between px-2.5 py-2 rounded-lg transition-colors ${
              isDark ? 'hover:bg-slate-800 text-slate-200' : 'hover:bg-slate-100 text-slate-700'
            }`}
          >
            <div className="flex items-center gap-2">
              <RefreshCw className="w-4 h-4 text-emerald-600 dark:text-emerald-400" />
              <span className="font-medium">检查更新...</span>
            </div>
            <span className="text-[11px] text-emerald-600 dark:text-emerald-400 font-mono">已是最新</span>
          </button>
        </div>
      </div>

      {/* Footer */}
      <div
        className={`px-4 py-2 border-t flex items-center justify-between text-[11px] ${
          isDark ? 'border-slate-800 bg-slate-950/80 text-slate-400' : 'border-slate-100 bg-slate-50 text-slate-500'
        }`}
      >
        <a
          href="https://shurufa.wang"
          target="_blank"
          rel="noopener noreferrer"
          className="hover:text-blue-600 dark:hover:text-blue-400 transition-colors flex items-center gap-1"
        >
          <span>shurufa.wang</span>
          <ExternalLink className="w-3 h-3" />
        </a>

        <button
          onClick={onClose}
          className="hover:text-red-600 dark:hover:text-red-400 transition-colors font-medium flex items-center gap-1"
        >
          <Power className="w-3 h-3" />
          <span>退出 GY输入法</span>
        </button>
      </div>
    </div>
  );
};
