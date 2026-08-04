import React, { useState } from 'react';
import { GYSystemAppIcon, GYSymbolPathSVG } from './GYWordmarkLogo';
import { Monitor, Apple, Type } from 'lucide-react';

export const SystemPreview: React.FC = () => {
  const [activeTab, setActiveTab] = useState<'win' | 'mac' | 'editor'>('win');

  return (
    <div className="w-full max-w-4xl mx-auto my-8 bg-neutral-50 dark:bg-neutral-900/60 rounded-2xl p-6 border border-neutral-200/80 dark:border-neutral-800 transition-all">
      <div className="flex flex-col sm:flex-row items-start sm:items-center justify-between pb-4 mb-6 border-b border-neutral-200 dark:border-neutral-800 gap-4">
        <div>
          <h3 className="text-sm font-semibold tracking-wider text-neutral-800 dark:text-neutral-200 uppercase font-mono">
            系统原生集成预览 / Native OS Integration
          </h3>
          <p className="text-xs text-neutral-500 dark:text-neutral-400 mt-1">
            大写字母 GY 在 Windows 任务栏、macOS 状态栏及打字跟手候选框中的自然融入
          </p>
        </div>

        {/* Tab Switcher */}
        <div className="flex items-center gap-1 bg-neutral-200/70 dark:bg-neutral-800 p-1 rounded-lg text-xs font-medium">
          <button
            onClick={() => setActiveTab('win')}
            className={`flex items-center gap-1.5 px-3 py-1.5 rounded-md transition-all cursor-pointer ${
              activeTab === 'win'
                ? 'bg-white dark:bg-neutral-700 text-neutral-900 dark:text-white shadow-xs'
                : 'text-neutral-600 dark:text-neutral-400 hover:text-neutral-900 dark:hover:text-white'
            }`}
          >
            <Monitor className="w-3.5 h-3.5" />
            <span>Windows 任务栏 (16px)</span>
          </button>
          <button
            onClick={() => setActiveTab('mac')}
            className={`flex items-center gap-1.5 px-3 py-1.5 rounded-md transition-all cursor-pointer ${
              activeTab === 'mac'
                ? 'bg-white dark:bg-neutral-700 text-neutral-900 dark:text-white shadow-xs'
                : 'text-neutral-600 dark:text-neutral-400 hover:text-neutral-900 dark:hover:text-white'
            }`}
          >
            <Apple className="w-3.5 h-3.5" />
            <span>macOS 状态栏 (16px)</span>
          </button>
          <button
            onClick={() => setActiveTab('editor')}
            className={`flex items-center gap-1.5 px-3 py-1.5 rounded-md transition-all cursor-pointer ${
              activeTab === 'editor'
                ? 'bg-white dark:bg-neutral-700 text-neutral-900 dark:text-white shadow-xs'
                : 'text-neutral-600 dark:text-neutral-400 hover:text-neutral-900 dark:hover:text-white'
            }`}
          >
            <Type className="w-3.5 h-3.5" />
            <span>打字跟手候选框</span>
          </button>
        </div>
      </div>

      {/* Preview Content Area */}
      <div className="overflow-hidden rounded-xl border border-neutral-200 dark:border-neutral-800 bg-white dark:bg-neutral-950 shadow-inner">
        {/* Windows Taskbar Preview */}
        {activeTab === 'win' && (
          <div className="bg-[#1e1e1e] text-white p-4 font-sans text-xs flex flex-col justify-between min-h-[160px]">
            <div className="text-neutral-400 text-[11px] mb-8 flex items-center justify-between">
              <span>Windows 11 托盘 / IME System Icon</span>
              <span className="text-[10px] text-neutral-500 font-mono">16px Icon + #111318 Dark Base</span>
            </div>
            {/* Taskbar mockup */}
            <div className="h-12 bg-[#202020] border-t border-neutral-800 rounded-lg px-4 flex items-center justify-between">
              <div className="flex items-center gap-3 text-neutral-400">
                <span className="w-4 h-4 rounded-xs border border-neutral-600 flex items-center justify-center text-[9px] font-bold">⊞</span>
                <span className="text-xs">搜索</span>
              </div>

              {/* System Tray Icons */}
              <div className="flex items-center gap-3">
                {/* GY IME Icon in Windows Tray */}
                <div className="flex items-center gap-1.5 bg-neutral-800/80 hover:bg-neutral-700/80 px-2 py-1 rounded transition-colors cursor-pointer border border-neutral-700/50">
                  <GYSystemAppIcon size={16} borderRadius={3} />
                  <span className="text-[11px] font-medium tracking-tight text-white border-l border-neutral-700 pl-1.5">中</span>
                </div>
                <span className="text-neutral-400 text-[11px]">21:40</span>
                <span className="text-neutral-500 text-[10px]">2026/8/1</span>
              </div>
            </div>
          </div>
        )}

        {/* macOS Menu Bar Preview */}
        {activeTab === 'mac' && (
          <div className="bg-neutral-100 dark:bg-neutral-900 text-neutral-800 dark:text-neutral-200 p-4 font-sans text-xs flex flex-col justify-between min-h-[160px]">
            <div className="text-neutral-500 text-[11px] mb-8 flex items-center justify-between">
              <span>macOS Status Item Bar</span>
              <span className="text-[10px] text-neutral-400 font-mono">16px Scale</span>
            </div>
            {/* Menu bar mockup */}
            <div className="h-9 bg-white/80 dark:bg-neutral-800/80 backdrop-blur-md rounded-md px-4 flex items-center justify-between border border-neutral-200/50 dark:border-neutral-700/50">
              <div className="flex items-center gap-4 text-xs font-medium">
                <Apple className="w-3.5 h-3.5 fill-current" />
                <span className="font-semibold">GY 输入法</span>
                <span className="text-neutral-500">文件</span>
                <span className="text-neutral-500">编辑</span>
              </div>

              <div className="flex items-center gap-3">
                <div className="flex items-center gap-1 p-0.5 rounded cursor-pointer">
                  <GYSystemAppIcon size={16} borderRadius={3} />
                </div>
                <span className="text-[11px] font-medium font-mono">周六 21:40</span>
              </div>
            </div>
          </div>
        )}

        {/* Editor Floating IME Candidates Bar Preview */}
        {activeTab === 'editor' && (
          <div className="bg-neutral-50 dark:bg-neutral-900 p-6 text-neutral-800 dark:text-neutral-200 font-sans text-sm flex flex-col justify-between min-h-[180px] relative overflow-hidden">
            <div className="text-neutral-400 text-[11px] mb-2 flex items-center justify-between">
              <span>打字跟手态 / Floating Candidate Window</span>
              <span className="text-[10px] text-neutral-400 font-mono">Clean & Professional IME Panel</span>
            </div>

            {/* Document Text */}
            <div className="font-serif leading-relaxed text-base text-neutral-700 dark:text-neutral-300 py-2">
              思想如流水般在屏幕上顺畅延展<span className="inline-block w-0.5 h-5 bg-neutral-900 dark:bg-white animate-pulse ml-0.5 vertical-middle" />
            </div>

            {/* Floating IME Candidate Box */}
            <div className="mt-3 inline-flex items-center gap-3 bg-white dark:bg-neutral-800 shadow-lg rounded-xl p-2.5 px-3 border border-neutral-200/90 dark:border-neutral-700/80 max-w-sm">
              <GYSystemAppIcon size={22} borderRadius={4} />
              <div className="flex items-center gap-2 text-xs">
                <span className="text-neutral-400 font-mono">1.</span>
                <span className="font-semibold text-neutral-900 dark:text-white">思想</span>
                <span className="text-neutral-400 font-mono">2.</span>
                <span className="text-neutral-600 dark:text-neutral-300">思考</span>
                <span className="text-neutral-400 font-mono">3.</span>
                <span className="text-neutral-600 dark:text-neutral-300">私想</span>
              </div>
            </div>
          </div>
        )}
      </div>
    </div>
  );
};
