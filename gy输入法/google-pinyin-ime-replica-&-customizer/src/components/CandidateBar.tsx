import React from 'react';
import { IMESettings } from '../types';
import { ChevronLeft, ChevronRight, Sparkles } from 'lucide-react';

interface CandidateBarProps {
  pinyin: string;
  candidates: string[];
  selectedIndex: number;
  pageIndex: number;
  settings: IMESettings;
  onSelectCandidate: (candidate: string, index: number) => void;
  onPrevPage: () => void;
  onNextPage: () => void;
  isInspectorMode?: boolean;
  isAiLoading?: boolean;
  mode?: 'zh' | 'en';
}

export const CandidateBar: React.FC<CandidateBarProps> = ({
  pinyin,
  candidates,
  selectedIndex,
  pageIndex,
  settings,
  onSelectCandidate,
  onPrevPage,
  onNextPage,
  isInspectorMode = false,
  isAiLoading = false,
  mode = 'zh',
}) => {
  // Scale factor based on High-DPI setting (e.g. 100% -> 1.0, 125% -> 1.25, 150% -> 1.5, 200% -> 2.0)
  const scale = settings.dpiScale / 100;

  const heightPx = Math.round(settings.height * scale);
  const radiusPx = Math.round(settings.borderRadius * scale);
  const paddingPx = Math.round(settings.padding * scale);
  const pinyinSizePx = Math.round(settings.pinyinFontSize * scale);
  const candidateSizePx = Math.round(settings.candidateFontSize * scale);
  const maxWidthPx = Math.round(settings.maxWidth * scale);

  // Pagination slice
  const maxPerPage = settings.maxCandidates;
  const totalPages = Math.ceil(candidates.length / maxPerPage) || 1;
  const currentPage = Math.min(pageIndex, totalPages - 1);
  const pageCandidates = candidates.slice(currentPage * maxPerPage, (currentPage + 1) * maxPerPage);

  // Shadow class based on intensity
  const shadowStyle = {
    none: 'none',
    subtle: '0 4px 12px rgba(0, 0, 0, 0.08), 0 1px 3px rgba(0, 0, 0, 0.05)',
    medium: '0 8px 24px rgba(0, 0, 0, 0.12), 0 2px 6px rgba(0, 0, 0, 0.08)',
    strong: '0 12px 32px rgba(0, 0, 0, 0.25), 0 4px 12px rgba(0, 0, 0, 0.15)',
  }[settings.shadowIntensity];

  return (
    <div className="relative inline-block selection:bg-none font-sans" style={{ fontFamily: settings.fontFamily }}>
      {/* Blueprint / Inspector Callout Overlays if Inspector Mode is enabled */}
      {isInspectorMode && (
        <div className="absolute -top-7 left-0 right-0 flex justify-between items-center text-[10px] text-blue-600 font-mono font-semibold px-1 pointer-events-none z-30">
          <span>H: {heightPx}px ({settings.dpiScale}% scale)</span>
          <span>R: {radiusPx}px</span>
          <span>Max: {maxWidthPx}px</span>
          <span>Candidates: {settings.maxCandidates}</span>
        </div>
      )}

      {/* Main IME Candidate Bar Container */}
      <div
        className="flex items-center backdrop-blur-md transition-all duration-150 select-none border relative overflow-hidden"
        style={{
          height: `${heightPx}px`,
          borderRadius: `${radiusPx}px`,
          paddingLeft: `${paddingPx}px`,
          paddingRight: `${paddingPx}px`,
          maxWidth: `${maxWidthPx}px`,
          backgroundColor: settings.nonSelectedBg,
          borderColor: settings.borderColor,
          boxShadow: shadowStyle,
          color: settings.textColor,
        }}
      >
        {/* Left Pinyin Input String Area */}
        <div className="flex items-center shrink-0 pr-2 border-r border-slate-200/40 mr-2">
          <span
            className="font-medium tracking-tight whitespace-nowrap leading-none flex items-center gap-1"
            style={{
              fontSize: `${pinyinSizePx}px`,
              color: settings.pinyinTextColor,
            }}
          >
            {pinyin || 'keyle'}
            {isAiLoading && (
              <Sparkles className="w-3 h-3 text-blue-500 animate-spin" />
            )}
          </span>
        </div>

        {/* Horizontal Single-Row Candidates List */}
        <div className="flex items-center gap-1 overflow-x-auto scrollbar-none py-1 my-auto flex-1">
          {pageCandidates.length === 0 ? (
            <span
              className="italic opacity-60 text-xs px-2"
              style={{ fontSize: `${pinyinSizePx}px` }}
            >
              无候选词
            </span>
          ) : (
            pageCandidates.map((word, idx) => {
              const overallIndex = currentPage * maxPerPage + idx;
              const isSelected = overallIndex === selectedIndex;
              const candidateNum = idx + 1;

              return (
                <button
                  key={`${word}-${idx}`}
                  onClick={() => onSelectCandidate(word, overallIndex)}
                  className="flex items-center shrink-0 transition-all duration-100 cursor-pointer rounded whitespace-nowrap leading-none focus:outline-none"
                  style={{
                    height: `${heightPx - paddingPx * 2}px`,
                    paddingLeft: `${Math.round(8 * scale)}px`,
                    paddingRight: `${Math.round(10 * scale)}px`,
                    backgroundColor: isSelected ? settings.selectedBgColor : 'transparent',
                    color: isSelected ? settings.selectedTextColor : settings.textColor,
                    borderRadius: isSelected ? `${Math.max(4, radiusPx - 2)}px` : '4px',
                  }}
                >
                  {/* Candidate Index Number (1-9) */}
                  {settings.showNumbers && (
                    <span
                      className="mr-1 font-sans font-normal opacity-90 select-none shrink-0"
                      style={{
                        fontSize: `${Math.max(10, Math.round(candidateSizePx * 0.75))}px`,
                        color: isSelected ? settings.selectedNumberColor : settings.numberColor,
                      }}
                    >
                      {candidateNum}
                    </span>
                  )}

                  {/* Candidate Hanzi Text */}
                  <span
                    className="font-semibold tracking-normal"
                    style={{
                      fontSize: `${candidateSizePx}px`,
                    }}
                  >
                    {word}
                  </span>
                </button>
              );
            })
          )}
        </div>

        {/* Persistent conversion-mode shortcut: a real discoverable control, not a hidden gesture. */}
        <div
          className="flex items-center gap-1 shrink-0 pl-2 ml-1 border-l border-slate-200/60 dark:border-slate-700/70"
          title="Ctrl + Space 切换中英文"
        >
          <span className="text-[10px] font-bold text-blue-600 dark:text-blue-300 rounded bg-blue-50 dark:bg-blue-950/60 px-1.5 py-0.5">
            {mode === 'zh' ? '中' : 'EN'}
          </span>
          <kbd className="text-[10px] font-mono text-slate-400 dark:text-slate-500 whitespace-nowrap">
            Ctrl+Space
          </kbd>
        </div>
        {/* Right Page Controls (If total candidates > maxPerPage) */}
        {totalPages > 1 && (
          <div className="flex items-center gap-0.5 shrink-0 pl-1 border-l border-slate-200/40 ml-1">
            <button
              onClick={onPrevPage}
              disabled={currentPage === 0}
              className="p-1 rounded hover:bg-slate-200/50 disabled:opacity-30 disabled:hover:bg-transparent transition-colors cursor-pointer"
              title="上一页 (,)"
            >
              <ChevronLeft className="w-3.5 h-3.5" />
            </button>
            <span className="text-[11px] font-mono opacity-70 px-0.5">
              {currentPage + 1}/{totalPages}
            </span>
            <button
              onClick={onNextPage}
              disabled={currentPage >= totalPages - 1}
              className="p-1 rounded hover:bg-slate-200/50 disabled:opacity-30 disabled:hover:bg-transparent transition-colors cursor-pointer"
              title="下一页 (.)"
            >
              <ChevronRight className="w-3.5 h-3.5" />
            </button>
          </div>
        )}
      </div>

      {/* Dimensional Measurement Callout Lines (When Inspector Mode is active) */}
      {isInspectorMode && (
        <div className="absolute -bottom-6 left-0 right-0 flex justify-between text-[10px] font-mono text-slate-500 px-1 pointer-events-none">
          <span className="bg-blue-100 text-blue-800 px-1 rounded">Pinyin: {pinyinSizePx}px</span>
          <span className="bg-blue-100 text-blue-800 px-1 rounded">Candidate: {candidateSizePx}px</span>
          <span className="bg-blue-100 text-blue-800 px-1 rounded">Pad: {paddingPx}px</span>
        </div>
      )}
    </div>
  );
};
