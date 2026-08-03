/**
 * @license
 * SPDX-License-Identifier: Apache-2.0
 */

import React, { useState } from 'react';
import { IMESettings } from './types';
import { THEME_PRESETS } from './data/themes';
import { DesktopPlayground } from './components/DesktopPlayground';
import { SpecStudio } from './components/SpecStudio';
import { DesignPromptCenter } from './components/DesignPromptCenter';
import { DictionaryEditor } from './components/DictionaryEditor';
import { Sparkles, Sliders, Keyboard, BookOpen, Layers, CheckCircle2 } from 'lucide-react';

const DEFAULT_SETTINGS: IMESettings = {
  height: 46,
  borderRadius: 8,
  padding: 8,
  pinyinFontSize: 14,
  candidateFontSize: 18,
  maxCandidates: 5,
  maxWidth: 640,
  selectedBgColor: '#2563EB',
  selectedTextColor: '#FFFFFF',
  nonSelectedBg: '#FFFFFF',
  textColor: '#0F172A',
  pinyinTextColor: '#64748B',
  numberColor: '#94A3B8',
  selectedNumberColor: '#93C5FD',
  borderColor: '#E2E8F0',
  shadowIntensity: 'subtle',
  dpiScale: 100,
  fontFamily: 'Segoe UI, "Microsoft YaHei", sans-serif',
  themePreset: 'google-blue',
  showNumbers: true,
  useAiEngine: false,
};

export default function App() {
  const [settings, setSettings] = useState<IMESettings>(DEFAULT_SETTINGS);
  const [isInspectorMode, setIsInspectorMode] = useState<boolean>(false);
  const [customDict, setCustomDict] = useState<Record<string, string[]>>({});

  const handleUpdateSettings = (newPartial: Partial<IMESettings>) => {
    setSettings((prev) => ({ ...prev, ...newPartial }));
  };

  const handleResetToBenchmark = () => {
    setSettings(DEFAULT_SETTINGS);
  };

  return (
    <div className="min-h-screen bg-slate-50 dark:bg-slate-950 text-slate-900 dark:text-slate-100 font-sans antialiased selection:bg-blue-500 selection:text-white pb-16">
      {/* Header Bar */}
      <header className="sticky top-0 z-40 bg-white/80 dark:bg-slate-900/80 backdrop-blur-md border-b border-slate-200 dark:border-slate-800 px-4 lg:px-8 py-3.5">
        <div className="max-w-7xl mx-auto flex flex-col sm:flex-row items-start sm:items-center justify-between gap-3">
          <div className="flex items-center gap-3">
            {/* Google Blue Inspired IME Icon */}
            <div className="w-9 h-9 rounded-xl bg-gradient-to-br from-blue-600 to-indigo-600 flex items-center justify-center text-white font-bold font-mono shadow-md text-sm">
              拼
            </div>
            <div>
              <div className="flex items-center gap-2">
                <h1 className="text-base font-bold text-slate-900 dark:text-white tracking-tight">
                  Google 拼音输入法复刻与设计规范调优仓
                </h1>
                <span className="hidden sm:inline-flex items-center gap-1 bg-blue-50 dark:bg-blue-950/80 text-blue-700 dark:text-blue-300 border border-blue-200 dark:border-blue-800 text-[10px] font-semibold px-2 py-0.5 rounded-full">
                  <CheckCircle2 className="w-3 h-3 text-blue-600" />
                  GY 100% 缩放基准
                </span>
              </div>
              <p className="text-xs text-slate-500 dark:text-slate-400">
                100% 缩放基准: 高度 46px | 圆角 8px | 内边距 8px | 拼音 14px | 候选 18px | 横向单行 5 候选
              </p>
            </div>
          </div>

          <div className="flex items-center gap-2">
            <button
              onClick={() => setIsInspectorMode(!isInspectorMode)}
              className={`text-xs font-semibold px-3 py-1.5 rounded-lg border transition-all cursor-pointer ${
                isInspectorMode
                  ? 'bg-blue-600 text-white border-blue-600 shadow-sm'
                  : 'bg-white dark:bg-slate-800 text-slate-700 dark:text-slate-300 border-slate-200 dark:border-slate-700 hover:bg-slate-50'
              }`}
            >
              {isInspectorMode ? '标尺模式 ON' : '开启像素测量标尺'}
            </button>
          </div>
        </div>
      </header>

      {/* Main Container */}
      <main className="max-w-7xl mx-auto px-4 lg:px-8 pt-6 flex flex-col gap-6">
        {/* Section 1: Simulated Desktop Typing Canvas (Interactive IME Playground) */}
        <section>
          <div className="mb-2 flex items-center justify-between">
            <h2 className="text-sm font-bold text-slate-700 dark:text-slate-300 flex items-center gap-2 uppercase tracking-wider">
              <Keyboard className="w-4 h-4 text-blue-600" />
              Windows 桌面实时打字演示 (Live IME Candidate Bar Replica)
            </h2>
          </div>
          <DesktopPlayground
            settings={settings}
            onUpdateSettings={handleUpdateSettings}
            isInspectorMode={isInspectorMode}
            onToggleInspector={() => setIsInspectorMode(!isInspectorMode)}
            customDict={customDict}
          />
        </section>

        {/* Section 2: Spec Studio & Custom Dictionary */}
        <section className="grid grid-cols-1 lg:grid-cols-3 gap-6">
          <div className="lg:col-span-2">
            <SpecStudio
              settings={settings}
              onUpdateSettings={handleUpdateSettings}
              onResetToBenchmark={handleResetToBenchmark}
            />
          </div>
          <div className="lg:col-span-1">
            <DictionaryEditor
              customDict={customDict}
              onUpdateDict={(newDict) => setCustomDict(newDict)}
            />
          </div>
        </section>

        {/* Section 3: Design Prompt Center & GY Specification Benchmark */}
        <section>
          <DesignPromptCenter settings={settings} />
        </section>
      </main>
    </div>
  );
}
