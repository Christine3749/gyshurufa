import React from 'react';
import { DpiScale, IMESettings, ThemePreset } from '../types';
import { THEME_PRESETS } from '../data/themes';
import { Sliders, RotateCcw, Palette, Layers, Monitor, Type } from 'lucide-react';

interface SpecStudioProps {
  settings: IMESettings;
  onUpdateSettings: (newSettings: Partial<IMESettings>) => void;
  onResetToBenchmark: () => void;
}

export const SpecStudio: React.FC<SpecStudioProps> = ({
  settings,
  onUpdateSettings,
  onResetToBenchmark,
}) => {
  const handleThemeChange = (presetId: ThemePreset) => {
    const found = THEME_PRESETS.find((t) => t.id === presetId);
    if (found) {
      onUpdateSettings({
        ...found.settings,
        themePreset: presetId,
      });
    }
  };

  return (
    <div className="bg-white dark:bg-slate-900 border border-slate-200 dark:border-slate-800 rounded-2xl p-5 shadow-xs flex flex-col gap-6">
      {/* Title & Reset Button */}
      <div className="flex items-center justify-between border-b border-slate-100 dark:border-slate-800 pb-3">
        <div className="flex items-center gap-2">
          <Sliders className="w-5 h-5 text-blue-600 dark:text-blue-400" />
          <h2 className="text-base font-bold text-slate-900 dark:text-slate-100">
            参数调优工作台 (Spec Studio)
          </h2>
        </div>
        <button
          onClick={onResetToBenchmark}
          className="flex items-center gap-1.5 text-xs font-semibold text-blue-600 hover:text-blue-700 bg-blue-50 dark:bg-blue-950/60 dark:text-blue-300 px-3 py-1.5 rounded-lg transition-colors cursor-pointer"
        >
          <RotateCcw className="w-3.5 h-3.5" />
          恢复 GY 100% 缩放标准
        </button>
      </div>

      {/* Theme Presets */}
      <div>
        <label className="text-xs font-semibold text-slate-500 dark:text-slate-400 uppercase tracking-wider mb-2.5 flex items-center gap-1.5">
          <Palette className="w-3.5 h-3.5" />
          视觉主题预设 (Theme Presets)
        </label>
        <div className="grid grid-cols-2 sm:grid-cols-4 gap-2.5">
          {THEME_PRESETS.map((t) => {
            const isSelected = settings.themePreset === t.id;
            return (
              <button
                key={t.id}
                onClick={() => handleThemeChange(t.id)}
                className={`p-3 rounded-xl border text-left transition-all cursor-pointer flex flex-col gap-2 ${
                  isSelected
                    ? 'border-blue-600 ring-2 ring-blue-500/20 bg-blue-50/50 dark:bg-blue-950/30'
                    : 'border-slate-200 dark:border-slate-800 hover:border-slate-300 dark:hover:border-slate-700'
                }`}
              >
                <div className="flex items-center justify-between">
                  <span
                    className="w-4 h-4 rounded-full inline-block border border-black/10 shadow-xs"
                    style={{ backgroundColor: t.previewColor }}
                  />
                  {isSelected && (
                    <span className="text-[10px] font-bold text-blue-600 dark:text-blue-400 uppercase tracking-wider">
                      Active
                    </span>
                  )}
                </div>
                <div>
                  <div className="text-xs font-semibold text-slate-800 dark:text-slate-200">
                    {t.name}
                  </div>
                </div>
              </button>
            );
          })}
        </div>
      </div>

      {/* High-DPI Scaling Preset Selector */}
      <div>
        <label className="text-xs font-semibold text-slate-500 dark:text-slate-400 uppercase tracking-wider mb-2 flex items-center gap-1.5">
          <Monitor className="w-3.5 h-3.5" />
          系统 DPI 缩放比例 (High-DPI Windows Scaling)
        </label>
        <div className="grid grid-cols-4 gap-2">
          {([100, 125, 150, 200] as DpiScale[]).map((scale) => {
            const isSelected = settings.dpiScale === scale;
            return (
              <button
                key={scale}
                onClick={() => onUpdateSettings({ dpiScale: scale })}
                className={`py-2 px-3 rounded-xl border text-center transition-all cursor-pointer ${
                  isSelected
                    ? 'bg-blue-600 text-white font-bold border-blue-600 shadow-sm'
                    : 'bg-slate-50 dark:bg-slate-800 border-slate-200 dark:border-slate-700 text-slate-700 dark:text-slate-300 hover:bg-slate-100'
                }`}
              >
                <div className="text-sm">{scale}%</div>
                <div className="text-[10px] opacity-75">
                  {scale === 100 ? '基准 1x' : `${scale / 100}x 等比`}
                </div>
              </button>
            );
          })}
        </div>
      </div>

      {/* Sliders Grid for Dimensions */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-5 pt-2 border-t border-slate-100 dark:border-slate-800">
        {/* Candidate Bar Height */}
        <div className="flex flex-col gap-1.5">
          <div className="flex justify-between items-center text-xs">
            <span className="font-medium text-slate-700 dark:text-slate-300">
              候选窗高度 (Height)
            </span>
            <span className="font-mono font-bold text-blue-600 dark:text-blue-400">
              {settings.height} px {settings.height === 46 && '(基准)'}
            </span>
          </div>
          <input
            type="range"
            min={36}
            max={64}
            value={settings.height}
            onChange={(e) => onUpdateSettings({ height: Number(e.target.value) })}
            className="accent-blue-600 cursor-pointer"
          />
        </div>

        {/* Border Radius */}
        <div className="flex flex-col gap-1.5">
          <div className="flex justify-between items-center text-xs">
            <span className="font-medium text-slate-700 dark:text-slate-300">
              圆角大小 (Corner Radius)
            </span>
            <span className="font-mono font-bold text-blue-600 dark:text-blue-400">
              {settings.borderRadius} px {settings.borderRadius === 8 && '(基准)'}
            </span>
          </div>
          <input
            type="range"
            min={0}
            max={24}
            value={settings.borderRadius}
            onChange={(e) => onUpdateSettings({ borderRadius: Number(e.target.value) })}
            className="accent-blue-600 cursor-pointer"
          />
        </div>

        {/* Container Padding */}
        <div className="flex flex-col gap-1.5">
          <div className="flex justify-between items-center text-xs">
            <span className="font-medium text-slate-700 dark:text-slate-300">
              内边距 (Padding)
            </span>
            <span className="font-mono font-bold text-blue-600 dark:text-blue-400">
              {settings.padding} px {settings.padding === 8 && '(基准)'}
            </span>
          </div>
          <input
            type="range"
            min={4}
            max={18}
            value={settings.padding}
            onChange={(e) => onUpdateSettings({ padding: Number(e.target.value) })}
            className="accent-blue-600 cursor-pointer"
          />
        </div>

        {/* Candidate Count */}
        <div className="flex flex-col gap-1.5">
          <div className="flex justify-between items-center text-xs">
            <span className="font-medium text-slate-700 dark:text-slate-300">
              默认每页候选数 (Candidates Page Size)
            </span>
            <span className="font-mono font-bold text-blue-600 dark:text-blue-400">
              {settings.maxCandidates} 个 {settings.maxCandidates === 5 && '(基准)'}
            </span>
          </div>
          <input
            type="range"
            min={3}
            max={9}
            value={settings.maxCandidates}
            onChange={(e) => onUpdateSettings({ maxCandidates: Number(e.target.value) })}
            className="accent-blue-600 cursor-pointer"
          />
        </div>

        {/* Pinyin Font Size */}
        <div className="flex flex-col gap-1.5">
          <div className="flex justify-between items-center text-xs">
            <span className="font-medium text-slate-700 dark:text-slate-300">
              拼音字号 (Pinyin Size)
            </span>
            <span className="font-mono font-bold text-blue-600 dark:text-blue-400">
              {settings.pinyinFontSize} px {settings.pinyinFontSize === 14 && '(基准)'}
            </span>
          </div>
          <input
            type="range"
            min={11}
            max={18}
            value={settings.pinyinFontSize}
            onChange={(e) => onUpdateSettings({ pinyinFontSize: Number(e.target.value) })}
            className="accent-blue-600 cursor-pointer"
          />
        </div>

        {/* Candidate Font Size */}
        <div className="flex flex-col gap-1.5">
          <div className="flex justify-between items-center text-xs">
            <span className="font-medium text-slate-700 dark:text-slate-300">
              候选字号 (Candidate Size)
            </span>
            <span className="font-mono font-bold text-blue-600 dark:text-blue-400">
              {settings.candidateFontSize} px {settings.candidateFontSize === 18 && '(基准)'}
            </span>
          </div>
          <input
            type="range"
            min={14}
            max={26}
            value={settings.candidateFontSize}
            onChange={(e) => onUpdateSettings({ candidateFontSize: Number(e.target.value) })}
            className="accent-blue-600 cursor-pointer"
          />
        </div>
      </div>

      {/* Colors & Typography Customize */}
      <div className="pt-2 border-t border-slate-100 dark:border-slate-800 flex flex-wrap items-center justify-between gap-4">
        <div className="flex items-center gap-3">
          <span className="text-xs font-semibold text-slate-500 uppercase tracking-wider flex items-center gap-1">
            <Type className="w-3.5 h-3.5" />
            首选色 (Primary Accent):
          </span>
          <div className="flex items-center gap-2">
            <input
              type="color"
              value={settings.selectedBgColor}
              onChange={(e) =>
                onUpdateSettings({
                  selectedBgColor: e.target.value,
                  themePreset: 'custom',
                })
              }
              className="w-7 h-7 rounded border border-slate-300 cursor-pointer p-0"
            />
            <span className="text-xs font-mono uppercase">{settings.selectedBgColor}</span>
          </div>
        </div>

        <div className="flex items-center gap-2">
          <label className="text-xs font-medium text-slate-600 dark:text-slate-300 flex items-center gap-1.5 cursor-pointer select-none">
            <input
              type="checkbox"
              checked={settings.showNumbers}
              onChange={(e) => onUpdateSettings({ showNumbers: e.target.checked })}
              className="rounded text-blue-600 accent-blue-600"
            />
            显示数字序号 (1-9)
          </label>
        </div>
      </div>
    </div>
  );
};
