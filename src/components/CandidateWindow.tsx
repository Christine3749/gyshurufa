import React, { useState } from 'react';
import { ChevronLeft, ChevronRight, ChevronDown, Lock, Sparkles, Keyboard, ShieldCheck } from 'lucide-react';
import { CandidateItem, UserSettings } from '../types';
import { formatPinyinSyllables } from '../lib/dictionary';

interface CandidateWindowProps {
  pinyin: string;
  candidates: CandidateItem[];
  selectedIndex: number;
  page: number;
  totalPages: number;
  settings: UserSettings;
  onSelectCandidate: (candidate: CandidateItem) => void;
  onPrevPage: () => void;
  onNextPage: () => void;
  onToggleAiPanel: () => void;
  onToggleInputMode?: () => void;
  position?: { top: number; left: number };
  isExpanded?: boolean;
  onToggleExpand?: () => void;
}

export const CandidateWindow: React.FC<CandidateWindowProps> = ({
  pinyin,
  candidates,
  selectedIndex,
  page,
  totalPages,
  settings,
  onSelectCandidate,
  onPrevPage,
  onNextPage,
  onToggleAiPanel,
  onToggleInputMode,
  isExpanded = false,
  onToggleExpand,
}) => {
  const [hoveredIdx, setHoveredIdx] = useState<number | null>(null);

  if (!pinyin) return null;

  const cornerRadius = settings.appearance.cornerRadius || 10;
  const opacity = (settings.appearance.candidateOpacity || 95) / 100;
  const fontSize = settings.appearance.candidateFontSize || 16;
  const isDark = settings.appearance.theme === 'dark';

  const formattedPinyin = formatPinyinSyllables(pinyin);

  return (
    <div
      id="candidate-window"
      style={{
        borderRadius: `${cornerRadius}px`,
        opacity: opacity,
        fontSize: `${fontSize}px`,
      }}
      className={`
        inline-flex flex-col select-none transition-all duration-150 ease-out z-50
        backdrop-blur-md shadow-xl border
        ${
          isDark
            ? 'bg-slate-900/95 border-slate-700/80 text-slate-100 shadow-slate-950/50'
            : 'bg-white/95 border-slate-200/90 text-slate-800 shadow-slate-300/40'
        }
        min-w-[320px] max-w-[580px]
      `}
    >
      {/* Top Bar: Pre-edit Pinyin string */}
      <div className={`px-3 py-1.5 flex items-center justify-between border-b text-xs ${
        isDark ? 'border-slate-800 text-slate-400 bg-slate-950/40' : 'border-slate-100 text-slate-500 bg-slate-50/60'
      } rounded-t-[${cornerRadius}px]`}>
        <div className="flex items-center gap-2 overflow-hidden">
          <span className="font-mono font-medium text-blue-600 dark:text-blue-400 tracking-wide text-[13px] truncate">
            {formattedPinyin}
          </span>
          <span className="text-[10px] px-1.5 py-0.2 rounded bg-blue-500/10 text-blue-600 dark:text-blue-300 font-medium">
            GY拼音
          </span>
        </div>

        <div className="flex items-center gap-1.5 shrink-0">
          <button
            onClick={onToggleAiPanel}
            title="触发 GY AI 助手 (Ctrl+Shift+A)"
            className="flex items-center gap-1 px-1.5 py-0.5 rounded text-[11px] font-medium transition-colors bg-blue-50 dark:bg-blue-950/80 text-blue-700 dark:text-blue-300 hover:bg-blue-100 dark:hover:bg-blue-900 border border-blue-200/60 dark:border-blue-800/60"
          >
            <Sparkles className="w-3 h-3 text-blue-600 dark:text-blue-400" />
            <span>AI 助手</span>
          </button>
        </div>
      </div>

      {/* Main Candidate Area */}
      <div className="p-2 flex items-center justify-between gap-2 overflow-x-auto">
        <div className="flex items-center gap-1.5 flex-wrap">
          {candidates.map((item, index) => {
            const isSelected = index === selectedIndex;
            const isFirst = index === 0;

            return (
              <button
                key={item.id || index}
                onClick={() => onSelectCandidate(item)}
                onMouseEnter={() => setHoveredIdx(index)}
                onMouseLeave={() => setHoveredIdx(null)}
                className={`
                  flex items-center gap-1.5 px-2.5 py-1 rounded-md transition-all cursor-pointer font-sans whitespace-nowrap
                  ${
                    isFirst || isSelected
                      ? isDark
                        ? 'bg-blue-950/70 text-blue-200 border border-blue-800/80 shadow-xs font-semibold'
                        : 'bg-blue-50/90 text-blue-900 border border-blue-200/90 shadow-xs font-semibold'
                      : isDark
                      ? 'hover:bg-slate-800/80 text-slate-200 border border-transparent'
                      : 'hover:bg-slate-100 text-slate-800 border border-transparent'
                  }
                `}
              >
                {/* Index hotkey number 1-9 */}
                <span
                  className={`text-[11px] font-mono px-1 py-0.2 rounded font-medium ${
                    isFirst || isSelected
                      ? 'bg-blue-600 text-white'
                      : isDark
                      ? 'text-slate-400 bg-slate-800'
                      : 'text-slate-400 bg-slate-100'
                  }`}
                >
                  {index + 1}
                </span>

                {/* Candidate Text */}
                <span className="tracking-tight">{item.text}</span>
              </button>
            );
          })}
        </div>

        {/* Right side navigation & page controls */}
        <div className="flex items-center gap-0.5 shrink-0 pl-1 border-l border-slate-200 dark:border-slate-800">
          <button
            onClick={onPrevPage}
            disabled={page <= 1}
            title="上一页 (Page Up)"
            className={`p-1 rounded transition-colors ${
              page <= 1
                ? 'opacity-30 cursor-not-allowed'
                : isDark
                ? 'hover:bg-slate-800 text-slate-300'
                : 'hover:bg-slate-100 text-slate-600'
            }`}
          >
            <ChevronLeft className="w-3.5 h-3.5" />
          </button>

          <span className="text-[11px] font-mono text-slate-400 px-1">
            {page}/{totalPages || 1}
          </span>

          <button
            onClick={onNextPage}
            disabled={page >= totalPages}
            title="下一页 (Page Down)"
            className={`p-1 rounded transition-colors ${
              page >= totalPages
                ? 'opacity-30 cursor-not-allowed'
                : isDark
                ? 'hover:bg-slate-800 text-slate-300'
                : 'hover:bg-slate-100 text-slate-600'
            }`}
          >
            <ChevronRight className="w-3.5 h-3.5" />
          </button>

          {onToggleExpand && (
            <button
              onClick={onToggleExpand}
              title={isExpanded ? '收起候选窗' : '展开更多候选'}
              className={`p-1 rounded transition-colors ${
                isDark ? 'hover:bg-slate-800 text-slate-300' : 'hover:bg-slate-100 text-slate-600'
              }`}
            >
              <ChevronDown className={`w-3.5 h-3.5 transition-transform ${isExpanded ? 'rotate-180' : ''}`} />
            </button>
          )}
        </div>
      </div>

      {/* Expanded Grid View if active */}
      {isExpanded && (
        <div className={`p-2.5 border-t grid grid-cols-3 gap-1.5 ${
          isDark ? 'border-slate-800 bg-slate-950/60' : 'border-slate-100 bg-slate-50/80'
        }`}>
          {candidates.slice(0, 9).map((item, idx) => (
            <button
              key={`exp-${item.id}-${idx}`}
              onClick={() => onSelectCandidate(item)}
              className={`flex items-center gap-2 p-1.5 rounded text-xs transition-colors border text-left ${
                idx === 0
                  ? isDark
                    ? 'bg-blue-950/80 border-blue-800 text-blue-200'
                    : 'bg-blue-50 border-blue-200 text-blue-900 font-medium'
                  : isDark
                  ? 'hover:bg-slate-800 border-slate-800 text-slate-300'
                  : 'hover:bg-white border-slate-200 text-slate-700'
              }`}
            >
              <span className="font-mono text-[10px] text-slate-400 w-3">{idx + 1}.</span>
              <span className="truncate">{item.text}</span>
            </button>
          ))}
        </div>
      )}

      {/* Bottom Status Bar */}
      <div
        className={`px-3 py-1 flex items-center justify-between text-[11px] border-t rounded-b-[${cornerRadius}px] ${
          isDark ? 'border-slate-800 text-slate-400 bg-slate-950/80' : 'border-slate-100 text-slate-500 bg-slate-50'
        }`}
      >
        <div className="flex items-center gap-3">
          <button
            onClick={onToggleInputMode}
            className="flex items-center gap-1 hover:text-blue-600 dark:hover:text-blue-400 font-medium transition-colors"
          >
            <Keyboard className="w-3 h-3 text-slate-400" />
            <span>{settings.general.defaultLanguage === 'zh' ? '中' : '英'}</span>
          </button>

          <span className="text-slate-300 dark:text-slate-700">•</span>

          <span className="font-mono">{settings.input.pinyinType === 'quanpin' ? '全拼' : '双拼'}</span>

          <span className="text-slate-300 dark:text-slate-700">•</span>

          <div className="flex items-center gap-1 text-emerald-600 dark:text-emerald-400 font-medium" title="GY输入法：基础词库全在本地处理，隐私零泄漏">
            <ShieldCheck className="w-3 h-3" />
            <span>隐私本地模式</span>
          </div>
        </div>

        <div className="text-[10px] font-mono text-slate-400">
          GSYEN GY 2.5
        </div>
      </div>
    </div>
  );
};
