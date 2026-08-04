import React, { useState, useEffect, useRef } from 'react';
import { EditorTheme, IMESettings } from '../types';
import { CandidateBar } from './CandidateBar';
import { getCandidatesForPinyin } from '../data/pinyinDict';
import {
  FileText,
  Code,
  MessageSquare,
  FileCode2,
  Sparkles,
  Keyboard,
  RotateCcw,
  SlidersHorizontal,
  Eye,
  Copy,
  Check
} from 'lucide-react';

interface DesktopPlaygroundProps {
  settings: IMESettings;
  onUpdateSettings: (newSettings: Partial<IMESettings>) => void;
  isInspectorMode: boolean;
  onToggleInspector: () => void;
  customDict: Record<string, string[]>;
}

export const DesktopPlayground: React.FC<DesktopPlaygroundProps> = ({
  settings,
  onUpdateSettings,
  isInspectorMode,
  onToggleInspector,
  customDict,
}) => {
  const [editorTheme, setEditorTheme] = useState<EditorTheme>('notepad');
  const [typedText, setTypedText] = useState<string>('使用谷歌拼音输入法，体验流畅打字：');
  const [pinyinInput, setPinyinInput] = useState<string>('keyle');
  const [isEnglishMode, setIsEnglishMode] = useState<boolean>(false);
  const [selectedIndex, setSelectedIndex] = useState<number>(0);
  const [pageIndex, setPageIndex] = useState<number>(0);
  const [candidates, setCandidates] = useState<string[]>([]);
  const [isAiLoading, setIsAiLoading] = useState<boolean>(false);
  const [copiedNotification, setCopiedNotification] = useState<boolean>(false);

  const inputRef = useRef<HTMLInputElement>(null);
  const editorAreaRef = useRef<HTMLDivElement>(null);

  // Quick preset Pinyin words to test immediately
  const PRESET_PINYIN_TESTS = [
    { label: 'keyle (用户示例)', pinyin: 'keyle' },
    { label: 'zhongguo (中国)', pinyin: 'zhongguo' },
    { label: 'gongzuo (工作)', pinyin: 'gongzuo' },
    { label: 'pinyin (拼音)', pinyin: 'pinyin' },
    { label: 'guge (谷歌)', pinyin: 'guge' },
    { label: 'chuda (触达)', pinyin: 'chuda' },
    { label: 'ce (测试)', pinyin: 'ce' },
  ];

  // Fetch candidates whenever pinyinInput or customDict or settings.useAiEngine changes
  useEffect(() => {
    if (isEnglishMode || !pinyinInput) {
      setCandidates([]);
      setSelectedIndex(0);
      setPageIndex(0);
      return;
    }

    let isMounted = true;

    if (settings.useAiEngine) {
      setIsAiLoading(true);
      fetch('/api/pinyin-ai', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ pinyin: pinyinInput, count: 10 }),
      })
        .then((res) => res.json())
        .then((data) => {
          if (isMounted) {
            if (data.candidates && Array.isArray(data.candidates) && data.candidates.length > 0) {
              setCandidates(data.candidates);
            } else {
              setCandidates(getCandidatesForPinyin(pinyinInput, customDict));
            }
            setIsAiLoading(false);
          }
        })
        .catch(() => {
          if (isMounted) {
            setCandidates(getCandidatesForPinyin(pinyinInput, customDict));
            setIsAiLoading(false);
          }
        });
    } else {
      setCandidates(getCandidatesForPinyin(pinyinInput, customDict));
      setIsAiLoading(false);
    }

    setSelectedIndex(0);
    setPageIndex(0);

    return () => {
      isMounted = false;
    };
  }, [pinyinInput, customDict, settings.useAiEngine, isEnglishMode]);

  // Handle keypresses for selection, backspace, numbers 1-9
  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.ctrlKey && e.code === 'Space') {
      e.preventDefault();
      setIsEnglishMode((previous) => !previous);
      setPinyinInput('');
      setSelectedIndex(0);
      setPageIndex(0);
      return;
    }
    // Never consume application commands such as Ctrl+C, Ctrl+V or Ctrl+F.
    if (e.ctrlKey || e.altKey || e.metaKey) return;
    if (!pinyinInput && isEnglishMode) {
      if (e.key.length === 1) {
        setTypedText((previous) => previous + e.key);
        e.preventDefault();
      }
      return;
    }
    if (!pinyinInput) {
      if (e.key.length === 1 && /[a-zA-Z]/.test(e.key)) {
        setPinyinInput(e.key.toLowerCase());
        e.preventDefault();
      }
      return;
    }

    // Numbers 1-9 select candidate on current page
    if (/^[1-9]$/.test(e.key)) {
      e.preventDefault();
      const num = parseInt(e.key, 10);
      const pageOffset = pageIndex * settings.maxCandidates;
      const targetIndex = pageOffset + (num - 1);
      if (targetIndex < candidates.length) {
        commitCandidate(candidates[targetIndex]);
      }
      return;
    }

    // Space or Enter commits selected candidate
    if (e.key === ' ' || e.key === 'Enter') {
      e.preventDefault();
      if (candidates.length > 0 && candidates[selectedIndex]) {
        commitCandidate(candidates[selectedIndex]);
      } else {
        // Commit raw pinyin
        commitCandidate(pinyinInput);
      }
      return;
    }

    // Left/Right arrow moves candidate selection
    if (e.key === 'ArrowRight') {
      e.preventDefault();
      setSelectedIndex((prev) => Math.min(prev + 1, candidates.length - 1));
      return;
    }
    if (e.key === 'ArrowLeft') {
      e.preventDefault();
      setSelectedIndex((prev) => Math.max(prev - 1, 0));
      return;
    }

    // Up/Down arrow or PageUp/PageDown changes candidate pages
    if (e.key === 'ArrowDown' || e.key === '.' || e.key === 'PageDown') {
      e.preventDefault();
      const maxPages = Math.ceil(candidates.length / settings.maxCandidates);
      setPageIndex((prev) => Math.min(prev + 1, maxPages - 1));
      return;
    }
    if (e.key === 'ArrowUp' || e.key === ',' || e.key === 'PageUp') {
      e.preventDefault();
      setPageIndex((prev) => Math.max(prev - 1, 0));
      return;
    }

    // Backspace deletes pinyin letter
    if (e.key === 'Backspace') {
      e.preventDefault();
      if (pinyinInput.length > 1) {
        setPinyinInput((prev) => prev.slice(0, -1));
      } else {
        setPinyinInput('');
      }
      return;
    }

    // Escape clears pinyin
    if (e.key === 'Escape') {
      e.preventDefault();
      setPinyinInput('');
      return;
    }

    // Type letter to append to pinyin
    if (e.key.length === 1 && /[a-zA-Z]/.test(e.key)) {
      e.preventDefault();
      setPinyinInput((prev) => prev + e.key.toLowerCase());
    }
  };

  const commitCandidate = (text: string) => {
    setTypedText((prev) => prev + text);
    setPinyinInput('');
    setSelectedIndex(0);
    setPageIndex(0);
  };

  const handleCopyText = () => {
    navigator.clipboard.writeText(typedText);
    setCopiedNotification(true);
    setTimeout(() => setCopiedNotification(false), 2000);
  };

  // Editor background and header styling
  const getThemeClasses = () => {
    switch (editorTheme) {
      case 'vscode':
        return {
          windowBg: 'bg-[#1E1E1E] text-[#D4D4D4] border-[#333333]',
          headerBg: 'bg-[#252526] text-[#CCCCCC] border-[#333333]',
          editorAreaBg: 'bg-[#1E1E1E]',
          cursorColor: 'bg-blue-400',
          title: 'main.ts - Visual Studio Code',
          icon: <Code className="w-4 h-4 text-blue-400" />,
        };
      case 'wechat':
        return {
          windowBg: 'bg-[#F3F3F3] text-[#191919] border-[#E2E2E2]',
          headerBg: 'bg-[#E6E6E6] text-[#2C2C2C] border-[#DCDCDC]',
          editorAreaBg: 'bg-[#FFFFFF]',
          cursorColor: 'bg-emerald-500',
          title: '微信电脑版 - 对话窗口',
          icon: <MessageSquare className="w-4 h-4 text-emerald-600" />,
        };
      case 'word':
        return {
          windowBg: 'bg-[#F3F4F6] text-[#111827] border-[#E5E7EB]',
          headerBg: 'bg-[#2B579A] text-white border-[#1B3E70]',
          editorAreaBg: 'bg-white shadow-md mx-auto my-4 max-w-2xl min-h-[220px]',
          cursorColor: 'bg-blue-700',
          title: 'Document1.docx - Microsoft Word',
          icon: <FileCode2 className="w-4 h-4 text-blue-200" />,
        };
      case 'notepad':
      default:
        return {
          windowBg: 'bg-white text-slate-800 border-slate-200 shadow-xl',
          headerBg: 'bg-slate-100 text-slate-700 border-slate-200',
          editorAreaBg: 'bg-white',
          cursorColor: 'bg-black',
          title: '无标题 - 记事本 (Windows 11 Desktop)',
          icon: <FileText className="w-4 h-4 text-blue-600" />,
        };
    }
  };

  const themeStyle = getThemeClasses();

  return (
    <div className="flex flex-col gap-4">
      {/* Top Bar Controls for Playground */}
      <div className="flex flex-wrap items-center justify-between gap-3 bg-white dark:bg-slate-900 p-3 rounded-xl border border-slate-200 dark:border-slate-800 shadow-xs">
        <div className="flex items-center gap-2">
          <span className="text-xs font-semibold text-slate-500 dark:text-slate-400 uppercase tracking-wider">
            桌面场景:
          </span>
          <div className="flex items-center gap-1 bg-slate-100 dark:bg-slate-800 p-1 rounded-lg">
            <button
              onClick={() => setEditorTheme('notepad')}
              className={`flex items-center gap-1.5 px-2.5 py-1 text-xs font-medium rounded-md transition-all ${
                editorTheme === 'notepad'
                  ? 'bg-white dark:bg-slate-700 text-blue-600 dark:text-blue-400 shadow-xs'
                  : 'text-slate-600 dark:text-slate-400 hover:text-slate-900'
              }`}
            >
              <FileText className="w-3.5 h-3.5" />
              记事本
            </button>
            <button
              onClick={() => setEditorTheme('vscode')}
              className={`flex items-center gap-1.5 px-2.5 py-1 text-xs font-medium rounded-md transition-all ${
                editorTheme === 'vscode'
                  ? 'bg-white dark:bg-slate-700 text-blue-600 dark:text-blue-400 shadow-xs'
                  : 'text-slate-600 dark:text-slate-400 hover:text-slate-900'
              }`}
            >
              <Code className="w-3.5 h-3.5" />
              VS Code
            </button>
            <button
              onClick={() => setEditorTheme('wechat')}
              className={`flex items-center gap-1.5 px-2.5 py-1 text-xs font-medium rounded-md transition-all ${
                editorTheme === 'wechat'
                  ? 'bg-white dark:bg-slate-700 text-emerald-600 dark:text-emerald-400 shadow-xs'
                  : 'text-slate-600 dark:text-slate-400 hover:text-slate-900'
              }`}
            >
              <MessageSquare className="w-3.5 h-3.5" />
              微信
            </button>
            <button
              onClick={() => setEditorTheme('word')}
              className={`flex items-center gap-1.5 px-2.5 py-1 text-xs font-medium rounded-md transition-all ${
                editorTheme === 'word'
                  ? 'bg-white dark:bg-slate-700 text-blue-600 dark:text-blue-400 shadow-xs'
                  : 'text-slate-600 dark:text-slate-400 hover:text-slate-900'
              }`}
            >
              <FileCode2 className="w-3.5 h-3.5" />
              Word
            </button>
          </div>
        </div>

        {/* Toggles: Blueprint Ruler / AI Engine */}
        <div className="flex items-center gap-2">
          <button
            onClick={onToggleInspector}
            className={`flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium rounded-lg border transition-all ${
              isInspectorMode
                ? 'bg-blue-50 border-blue-300 text-blue-700 font-semibold dark:bg-blue-950 dark:border-blue-800 dark:text-blue-300'
                : 'bg-white border-slate-200 text-slate-700 hover:bg-slate-50 dark:bg-slate-800 dark:border-slate-700 dark:text-slate-300'
            }`}
          >
            <Eye className="w-3.5 h-3.5" />
            {isInspectorMode ? '已开启像素标尺' : '标尺测量模式'}
          </button>

          <button
            onClick={() => {
              setIsEnglishMode((previous) => !previous);
              setPinyinInput('');
            }}
            className={`flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium rounded-lg border transition-all ${
              isEnglishMode
                ? 'bg-slate-800 border-slate-700 text-white dark:bg-slate-100 dark:text-slate-900'
                : 'bg-blue-50 border-blue-200 text-blue-700 dark:bg-blue-950 dark:border-blue-800 dark:text-blue-300'
            }`}
            title="Ctrl + Space 切换中英文"
          >
            <Keyboard className="w-3.5 h-3.5" />
            {isEnglishMode ? 'EN · Ctrl+Space' : '中 · Ctrl+Space'}
          </button>
          <button
            onClick={() => onUpdateSettings({ useAiEngine: !settings.useAiEngine })}
            className={`flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium rounded-lg border transition-all ${
              settings.useAiEngine
                ? 'bg-amber-50 border-amber-300 text-amber-800 font-semibold dark:bg-amber-950 dark:border-amber-800 dark:text-amber-300'
                : 'bg-white border-slate-200 text-slate-700 hover:bg-slate-50 dark:bg-slate-800 dark:border-slate-700 dark:text-slate-300'
            }`}
            title="开启后任意拼音均可由 Gemini AI 实时生成上下文候选"
          >
            <Sparkles className="w-3.5 h-3.5 text-amber-500" />
            {settings.useAiEngine ? 'AI 智能引擎 ON' : '词库模式'}
          </button>

          <button
            onClick={() => {
              setTypedText('');
              setPinyinInput('keyle');
            }}
            className="p-1.5 text-slate-500 hover:text-slate-700 dark:text-slate-400 dark:hover:text-slate-200 rounded-lg hover:bg-slate-100 dark:hover:bg-slate-800"
            title="清空重置"
          >
            <RotateCcw className="w-4 h-4" />
          </button>
        </div>
      </div>

      {/* Simulated Windows Desktop Window Frame */}
      <div
        tabIndex={0}
        onKeyDown={handleKeyDown}
        className={`rounded-2xl border overflow-hidden transition-all duration-200 focus:outline-none focus:ring-2 focus:ring-blue-500/50 ${themeStyle.windowBg}`}
      >
        {/* Window Title Bar */}
        <div
          className={`flex items-center justify-between px-4 py-2.5 text-xs font-medium border-b select-none ${themeStyle.headerBg}`}
        >
          <div className="flex items-center gap-2">
            {themeStyle.icon}
            <span>{themeStyle.title}</span>
          </div>
          <div className="flex items-center gap-2">
            <span className="text-[10px] opacity-60 font-mono">DPI: {settings.dpiScale}%</span>
            <div className="flex items-center gap-1.5 ml-2">
              <span className="w-3 h-3 rounded-full bg-amber-400/80 inline-block"></span>
              <span className="w-3 h-3 rounded-full bg-emerald-400/80 inline-block"></span>
              <span className="w-3 h-3 rounded-full bg-rose-400/80 inline-block"></span>
            </div>
          </div>
        </div>

        {/* Editor Content Canvas */}
        <div
          ref={editorAreaRef}
          onClick={() => inputRef.current?.focus()}
          className={`p-6 min-h-[260px] relative font-sans cursor-text ${themeStyle.editorAreaBg}`}
        >
          <div className="text-base leading-relaxed tracking-normal whitespace-pre-wrap break-all">
            {typedText}

            {/* Blinking Cursor + Floating Candidate Bar */}
            <span className="inline-relative items-baseline">
              <span className={`inline-block w-[2px] h-5 align-sub animate-pulse ${themeStyle.cursorColor}`} />

              {/* IME Floating Candidate Bar Positioned Below Cursor */}
              {pinyinInput && !isEnglishMode && (
                <div className="absolute top-6 left-0 z-20 pt-1">
                  <CandidateBar
                    pinyin={pinyinInput}
                    candidates={candidates}
                    selectedIndex={selectedIndex}
                    pageIndex={pageIndex}
                    settings={settings}
                    onSelectCandidate={(candidate) => commitCandidate(candidate)}
                    onPrevPage={() => setPageIndex((p) => Math.max(0, p - 1))}
                    onNextPage={() =>
                      setPageIndex((p) =>
                        Math.min(Math.ceil(candidates.length / settings.maxCandidates) - 1, p + 1)
                      )
                    }
                    isInspectorMode={isInspectorMode}
                    isAiLoading={isAiLoading}
                    mode={isEnglishMode ? 'en' : 'zh'}
                  />
                </div>
              )}
            </span>
          </div>

          {!pinyinInput && (
            <div className="mt-8 text-xs text-slate-400 dark:text-slate-500 font-mono border-t border-dashed border-slate-200 dark:border-slate-800 pt-3 flex items-center justify-between">
              <span>{isEnglishMode ? '英文模式：直接输入英文；Ctrl+Space 切回中文' : '中文模式：1-5 选词，Space/Enter 确认，PageUp/PageDown 翻页；Ctrl+Space 切英文'}</span>
              <button
                onClick={handleCopyText}
                className="flex items-center gap-1 text-blue-600 hover:underline cursor-pointer"
              >
                {copiedNotification ? <Check className="w-3.5 h-3.5 text-emerald-600" /> : <Copy className="w-3.5 h-3.5" />}
                {copiedNotification ? '已复制已打字内容' : '复制已输入文本'}
              </button>
            </div>
          )}
        </div>
      </div>

      {/* Quick Pinyin Test Presets */}
      <div className="flex items-center gap-2 overflow-x-auto pb-1">
        <span className="text-xs font-medium text-slate-500 shrink-0 flex items-center gap-1">
          <Keyboard className="w-3.5 h-3.5" />
          快捷测试拼音:
        </span>
        <div className="flex items-center gap-1.5">
          {PRESET_PINYIN_TESTS.map((item) => (
            <button
              key={item.pinyin}
              onClick={() => {
                setPinyinInput(item.pinyin);
                setSelectedIndex(0);
                setPageIndex(0);
              }}
              className="px-2.5 py-1 text-xs font-mono bg-slate-100 hover:bg-blue-50 hover:text-blue-600 dark:bg-slate-800 dark:hover:bg-slate-700 dark:text-slate-300 rounded-md transition-colors cursor-pointer shrink-0"
            >
              {item.label}
            </button>
          ))}
        </div>
      </div>
    </div>
  );
};
