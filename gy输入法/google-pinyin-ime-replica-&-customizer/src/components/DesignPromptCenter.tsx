import React, { useState } from 'react';
import { IMESettings } from '../types';
import { Copy, Check, Sparkles, Code2, Table, FileCode } from 'lucide-react';

interface DesignPromptCenterProps {
  settings: IMESettings;
}

export const DesignPromptCenter: React.FC<DesignPromptCenterProps> = ({ settings }) => {
  const [activeTab, setActiveTab] = useState<'prompt' | 'benchmark' | 'css' | 'json'>('benchmark');
  const [copiedKey, setCopiedKey] = useState<string | null>(null);

  // Exact English Prompt from user request
  const AI_IMAGE_PROMPT = `Design a Windows desktop Chinese Pinyin IME candidate bar inspired by the clarity and restraint of early Google Pinyin Input Method, but do not copy Google logos or trademarks.

Single horizontal floating candidate bar, 5 candidates on one row, never vertical.
Clean light surface, subtle shadow, 8px rounded corners, compact 46px height at 100% Windows scaling.
Left side shows small gray pinyin text: “keyle”.
Then five horizontal candidate chips:
1 可以了 (selected, Google-blue #2563EB, white text)
2 客运量
3 可用来
4 柯有伦
5 可又来

Use Segoe UI / Microsoft YaHei style typography.
Pinyin 14px, candidates 18px semibold.
Minimal, quiet, high-density desktop utility UI.
No title bar, no footer tips, no AI panel, no icons except candidate numbers.
Place the bar directly below a text cursor inside a dark Windows desktop app.
High-DPI Windows 11 native UI mockup, pixel-perfect, practical, elegant.`;

  // Generated Tailwind / CSS Snippet matching current settings
  const tailwindSnippet = `<div className="flex items-center h-[${settings.height}px] max-w-[${settings.maxWidth}px] rounded-[${settings.borderRadius}px] p-[${settings.padding}px] bg-[${settings.nonSelectedBg}] border border-[${settings.borderColor}] shadow-md font-sans">
  <!-- Pinyin Input Area -->
  <span className="text-[${settings.pinyinFontSize}px] text-[${settings.pinyinTextColor}] font-medium pr-2 border-r border-slate-200">
    keyle
  </span>

  <!-- Candidate Chips (Single Row Horizontal) -->
  <div className="flex items-center gap-1 pl-2 overflow-x-auto">
    <!-- Candidate 1 (Selected) -->
    <button className="flex items-center h-full px-2.5 rounded bg-[${settings.selectedBgColor}] text-[${settings.selectedTextColor}] font-semibold text-[${settings.candidateFontSize}px]">
      <span className="text-xs opacity-80 mr-1">1</span>
      可以了
    </button>
    <!-- Candidates 2..5 -->
    <button className="flex items-center h-full px-2 text-slate-800 font-semibold text-[${settings.candidateFontSize}px]">
      <span className="text-xs text-slate-400 mr-1">2</span>
      客运量
    </button>
  </div>
</div>`;

  // JSON Design Tokens
  const jsonTokens = JSON.stringify(
    {
      imeSpec: 'Google Pinyin Replica Benchmark',
      dimensions: {
        heightPx: settings.height,
        borderRadiusPx: settings.borderRadius,
        paddingPx: settings.padding,
        pinyinFontSizePx: settings.pinyinFontSize,
        candidateFontSizePx: settings.candidateFontSize,
        maxCandidatesPerPage: settings.maxCandidates,
        maxWidthPx: settings.maxWidth,
        dpiScalePercent: settings.dpiScale,
      },
      colors: {
        selectedPrimary: settings.selectedBgColor,
        selectedText: settings.selectedTextColor,
        surfaceBackground: settings.nonSelectedBg,
        textColor: settings.textColor,
        pinyinColor: settings.pinyinTextColor,
        borderColor: settings.borderColor,
      },
      typography: {
        fontFamily: settings.fontFamily,
        layout: 'horizontal-single-row',
      },
    },
    null,
    2
  );

  const handleCopy = (text: string, key: string) => {
    navigator.clipboard.writeText(text);
    setCopiedKey(key);
    setTimeout(() => setCopiedKey(null), 2000);
  };

  return (
    <div className="bg-white dark:bg-slate-900 border border-slate-200 dark:border-slate-800 rounded-2xl p-5 shadow-xs flex flex-col gap-4">
      {/* Navigation Tabs */}
      <div className="flex flex-wrap items-center justify-between gap-2 border-b border-slate-100 dark:border-slate-800 pb-3">
        <div className="flex items-center gap-1.5 bg-slate-100 dark:bg-slate-800 p-1 rounded-xl">
          <button
            onClick={() => setActiveTab('benchmark')}
            className={`flex items-center gap-1.5 px-3 py-1.5 text-xs font-semibold rounded-lg transition-all cursor-pointer ${
              activeTab === 'benchmark'
                ? 'bg-white dark:bg-slate-700 text-blue-600 dark:text-blue-400 shadow-xs'
                : 'text-slate-600 dark:text-slate-400 hover:text-slate-900'
            }`}
          >
            <Table className="w-3.5 h-3.5" />
            GY 规格基准表
          </button>
          <button
            onClick={() => setActiveTab('prompt')}
            className={`flex items-center gap-1.5 px-3 py-1.5 text-xs font-semibold rounded-lg transition-all cursor-pointer ${
              activeTab === 'prompt'
                ? 'bg-white dark:bg-slate-700 text-blue-600 dark:text-blue-400 shadow-xs'
                : 'text-slate-600 dark:text-slate-400 hover:text-slate-900'
            }`}
          >
            <Sparkles className="w-3.5 h-3.5 text-amber-500" />
            AI 绘图提示词 (Prompt)
          </button>
          <button
            onClick={() => setActiveTab('css')}
            className={`flex items-center gap-1.5 px-3 py-1.5 text-xs font-semibold rounded-lg transition-all cursor-pointer ${
              activeTab === 'css'
                ? 'bg-white dark:bg-slate-700 text-blue-600 dark:text-blue-400 shadow-xs'
                : 'text-slate-600 dark:text-slate-400 hover:text-slate-900'
            }`}
          >
            <Code2 className="w-3.5 h-3.5" />
            Tailwind CSS
          </button>
          <button
            onClick={() => setActiveTab('json')}
            className={`flex items-center gap-1.5 px-3 py-1.5 text-xs font-semibold rounded-lg transition-all cursor-pointer ${
              activeTab === 'json'
                ? 'bg-white dark:bg-slate-700 text-blue-600 dark:text-blue-400 shadow-xs'
                : 'text-slate-600 dark:text-slate-400 hover:text-slate-900'
            }`}
          >
            <FileCode className="w-3.5 h-3.5" />
            JSON Tokens
          </button>
        </div>
      </div>

      {/* Tab 1: GY Benchmark Specification Matrix Table */}
      {activeTab === 'benchmark' && (
        <div className="flex flex-col gap-3">
          <div className="flex items-center justify-between">
            <h3 className="text-xs font-bold text-slate-700 dark:text-slate-300 uppercase tracking-wider">
              Google 风格复刻基准规格矩阵 (100% Windows 缩放)
            </h3>
            <span className="text-[11px] text-slate-500 font-mono">
              数据源: Google 拼音官方帮助 & GY 标准
            </span>
          </div>

          <div className="overflow-x-auto rounded-xl border border-slate-200 dark:border-slate-800">
            <table className="w-full text-left text-xs">
              <thead className="bg-slate-50 dark:bg-slate-800/60 text-slate-500 font-semibold uppercase">
                <tr>
                  <th className="py-2.5 px-3">项目</th>
                  <th className="py-2.5 px-3 text-right">100% 缩放基准</th>
                  <th className="py-2.5 px-3 text-right text-blue-600 dark:text-blue-400">
                    当前调优数值 ({settings.dpiScale}%)
                  </th>
                  <th className="py-2.5 px-3">说明</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100 dark:divide-slate-800 text-slate-700 dark:text-slate-300">
                <tr>
                  <td className="py-2 px-3 font-semibold">候选窗高度</td>
                  <td className="py-2 px-3 text-right font-mono font-bold">46 px</td>
                  <td className="py-2 px-3 text-right font-mono text-blue-600 dark:text-blue-400 font-bold">
                    {Math.round((settings.height * settings.dpiScale) / 100)} px
                  </td>
                  <td className="py-2 px-3 text-slate-500">高 DPI 按缩放等比放大</td>
                </tr>
                <tr>
                  <td className="py-2 px-3 font-semibold">圆角 (Corner Radius)</td>
                  <td className="py-2 px-3 text-right font-mono font-bold">8 px</td>
                  <td className="py-2 px-3 text-right font-mono text-blue-600 dark:text-blue-400 font-bold">
                    {Math.round((settings.borderRadius * settings.dpiScale) / 100)} px
                  </td>
                  <td className="py-2 px-3 text-slate-500">Win11 风格微圆角</td>
                </tr>
                <tr>
                  <td className="py-2 px-3 font-semibold">内边距 (Padding)</td>
                  <td className="py-2 px-3 text-right font-mono font-bold">8 px</td>
                  <td className="py-2 px-3 text-right font-mono text-blue-600 dark:text-blue-400 font-bold">
                    {Math.round((settings.padding * settings.dpiScale) / 100)} px
                  </td>
                  <td className="py-2 px-3 text-slate-500">紧凑高密度外框间距</td>
                </tr>
                <tr>
                  <td className="py-2 px-3 font-semibold">拼音字号</td>
                  <td className="py-2 px-3 text-right font-mono font-bold">14 px</td>
                  <td className="py-2 px-3 text-right font-mono text-blue-600 dark:text-blue-400 font-bold">
                    {Math.round((settings.pinyinFontSize * settings.dpiScale) / 100)} px
                  </td>
                  <td className="py-2 px-3 text-slate-500">左侧小字号灰色辅助拼音</td>
                </tr>
                <tr>
                  <td className="py-2 px-3 font-semibold">候选字号</td>
                  <td className="py-2 px-3 text-right font-mono font-bold">18 px</td>
                  <td className="py-2 px-3 text-right font-mono text-blue-600 dark:text-blue-400 font-bold">
                    {Math.round((settings.candidateFontSize * settings.dpiScale) / 100)} px
                  </td>
                  <td className="py-2 px-3 text-slate-500">Semibold 易读汉字候选</td>
                </tr>
                <tr>
                  <td className="py-2 px-3 font-semibold">默认候选数</td>
                  <td className="py-2 px-3 text-right font-mono font-bold">5 个</td>
                  <td className="py-2 px-3 text-right font-mono text-blue-600 dark:text-blue-400 font-bold">
                    {settings.maxCandidates} 个
                  </td>
                  <td className="py-2 px-3 text-slate-500">官方允许 3–9 个配置</td>
                </tr>
                <tr>
                  <td className="py-2 px-3 font-semibold">候选排列</td>
                  <td className="py-2 px-3 text-right font-mono font-bold">单行横向</td>
                  <td className="py-2 px-3 text-right font-mono text-blue-600 dark:text-blue-400 font-bold">
                    单行横向
                  </td>
                  <td className="py-2 px-3 text-slate-500">绝不使用竖向列表</td>
                </tr>
                <tr>
                  <td className="py-2 px-3 font-semibold">最大宽度</td>
                  <td className="py-2 px-3 text-right font-mono font-bold">640 px</td>
                  <td className="py-2 px-3 text-right font-mono text-blue-600 dark:text-blue-400 font-bold">
                    {Math.round((settings.maxWidth * settings.dpiScale) / 100)} px
                  </td>
                  <td className="py-2 px-3 text-slate-500">避免横向无限延伸</td>
                </tr>
                <tr>
                  <td className="py-2 px-3 font-semibold">首选高亮色</td>
                  <td className="py-2 px-3 text-right font-mono font-bold">#2563EB</td>
                  <td className="py-2 px-3 text-right font-mono text-blue-600 dark:text-blue-400 font-bold flex items-center justify-end gap-1">
                    <span
                      className="w-3 h-3 rounded-full inline-block border"
                      style={{ backgroundColor: settings.selectedBgColor }}
                    />
                    {settings.selectedBgColor}
                  </td>
                  <td className="py-2 px-3 text-slate-500">谷歌蓝或高对比度强选中</td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      )}

      {/* Tab 2: AI Image Generation Prompt */}
      {activeTab === 'prompt' && (
        <div className="flex flex-col gap-2">
          <div className="flex items-center justify-between">
            <span className="text-xs font-bold text-slate-700 dark:text-slate-300">
              用于 Gemini / Imagen / Midjourney 的经典英文 Prompt:
            </span>
            <button
              onClick={() => handleCopy(AI_IMAGE_PROMPT, 'prompt')}
              className="flex items-center gap-1.5 text-xs font-medium text-blue-600 dark:text-blue-400 hover:underline cursor-pointer"
            >
              {copiedKey === 'prompt' ? <Check className="w-3.5 h-3.5 text-emerald-600" /> : <Copy className="w-3.5 h-3.5" />}
              {copiedKey === 'prompt' ? '已复制 Prompt' : '一键复制英文 Prompt'}
            </button>
          </div>
          <pre className="bg-slate-900 text-slate-100 p-4 rounded-xl text-xs font-mono whitespace-pre-wrap leading-relaxed overflow-x-auto selection:bg-blue-500">
            {AI_IMAGE_PROMPT}
          </pre>
        </div>
      )}

      {/* Tab 3: Tailwind CSS Code Snippet */}
      {activeTab === 'css' && (
        <div className="flex flex-col gap-2">
          <div className="flex items-center justify-between">
            <span className="text-xs font-bold text-slate-700 dark:text-slate-300">
              当前配置的 Tailwind CSS 代码:
            </span>
            <button
              onClick={() => handleCopy(tailwindSnippet, 'css')}
              className="flex items-center gap-1.5 text-xs font-medium text-blue-600 dark:text-blue-400 hover:underline cursor-pointer"
            >
              {copiedKey === 'css' ? <Check className="w-3.5 h-3.5 text-emerald-600" /> : <Copy className="w-3.5 h-3.5" />}
              {copiedKey === 'css' ? '已复制 CSS' : '复制 Tailwind HTML'}
            </button>
          </div>
          <pre className="bg-slate-900 text-emerald-400 p-4 rounded-xl text-xs font-mono whitespace-pre-wrap leading-relaxed overflow-x-auto selection:bg-blue-500">
            {tailwindSnippet}
          </pre>
        </div>
      )}

      {/* Tab 4: JSON Tokens Exporter */}
      {activeTab === 'json' && (
        <div className="flex flex-col gap-2">
          <div className="flex items-center justify-between">
            <span className="text-xs font-bold text-slate-700 dark:text-slate-300">
              UI 设计 Tokens JSON (供开发者 / Figma 导入):
            </span>
            <button
              onClick={() => handleCopy(jsonTokens, 'json')}
              className="flex items-center gap-1.5 text-xs font-medium text-blue-600 dark:text-blue-400 hover:underline cursor-pointer"
            >
              {copiedKey === 'json' ? <Check className="w-3.5 h-3.5 text-emerald-600" /> : <Copy className="w-3.5 h-3.5" />}
              {copiedKey === 'json' ? '已复制 JSON' : '复制 JSON Tokens'}
            </button>
          </div>
          <pre className="bg-slate-900 text-amber-300 p-4 rounded-xl text-xs font-mono whitespace-pre-wrap leading-relaxed overflow-x-auto selection:bg-blue-500">
            {jsonTokens}
          </pre>
        </div>
      )}
    </div>
  );
};
