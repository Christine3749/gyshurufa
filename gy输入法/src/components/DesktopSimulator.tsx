import React, { useState, useRef, useEffect } from 'react';
import {
  Monitor,
  Maximize2,
  FileText,
  MessageSquare,
  Sparkles,
  Sliders,
  ShieldCheck,
  HelpCircle,
  RefreshCw,
  Search,
  Globe,
  Keyboard,
  Moon,
  Sun,
  Layout,
  ExternalLink,
  ChevronRight,
  Info
} from 'lucide-react';
import { UserSettings, CandidateItem } from '../types';
import { CandidateWindow } from './CandidateWindow';
import { TrayMenu } from './TrayMenu';
import { AiAssistantPanel } from './AiAssistantPanel';
import { SettingsLayout } from './SettingsLayout';
import { OnboardingModal } from './OnboardingModal';
import { getCandidatesForPinyin } from '../lib/dictionary';
import { GYBrandLogo } from './GYBrandLogo';

interface DesktopSimulatorProps {
  settings: UserSettings;
  onUpdateSettings: (updater: (prev: UserSettings) => UserSettings) => void;
}

export const DesktopSimulator: React.FC<DesktopSimulatorProps> = ({
  settings,
  onUpdateSettings,
}) => {
  // App states
  const [activeTab, setActiveTab] = useState<'notepad' | 'doc' | 'chat'>('notepad');
  const [showSettingsModal, setShowSettingsModal] = useState(false);
  const [settingsTab, setSettingsTab] = useState('general');
  const [showTrayMenu, setShowTrayMenu] = useState(false);
  const [showAiPanel, setShowAiPanel] = useState(false);
  const [showOnboarding, setShowOnboarding] = useState(false);

  // Live Typing Engine State
  const [pinyinInput, setPinyinInput] = useState('gyshurufa');
  const [page, setPage] = useState(1);
  const [selectedCandidateIdx, setSelectedCandidateIdx] = useState(0);
  const [candidateWindowExpanded, setCandidateWindowExpanded] = useState(false);
  
  // Document Text Buffer
  const [notepadText, setNotepadText] = useState(
    'GY输入法是 GSYEN 旗下专为 Windows 平台打造的精细中文输入系统。\n\n你可以直接在此处尝试打字：gyshurufa'
  );

  const [docText, setDocText] = useState(
    'GY输入法核心理念：快、准、本地优先。AI 助手只会在您主动按下 Ctrl+Shift+A 或点击 AI 按钮时触发。请选中本段文字，点击右上角“AI 润色”进行测试。'
  );

  const [selectedDocText, setSelectedDocText] = useState('');

  const isDark = settings.appearance.theme === 'dark';

  // Compute Candidates
  const candidatesPerPage = settings.input.candidateCount || 5;
  const allCandidates = getCandidatesForPinyin(pinyinInput, 20);
  const totalPages = Math.ceil(allCandidates.length / candidatesPerPage) || 1;
  const currentCandidates = allCandidates.slice(
    (page - 1) * candidatesPerPage,
    page * candidatesPerPage
  );

  // Keybindings listener for interactive prototype
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      // Shortcut Ctrl+Shift+A for AI panel
      if ((e.ctrlKey || e.metaKey) && e.shiftKey && e.key.toLowerCase() === 'a') {
        e.preventDefault();
        setShowAiPanel(true);
        return;
      }

      // Shortcut Win/Alt+Shift+S for settings
      if ((e.ctrlKey || e.metaKey) && e.shiftKey && e.key.toLowerCase() === 's') {
        e.preventDefault();
        setShowSettingsModal(true);
        return;
      }

      // If active candidate window and focus in input
      if (pinyinInput) {
        if (e.key >= '1' && e.key <= '9') {
          const num = parseInt(e.key) - 1;
          if (num < currentCandidates.length) {
            e.preventDefault();
            handleSelectCandidate(currentCandidates[num]);
          }
        } else if (e.key === ' ' || e.key === 'Enter') {
          if (currentCandidates.length > 0) {
            e.preventDefault();
            handleSelectCandidate(currentCandidates[selectedCandidateIdx] || currentCandidates[0]);
          }
        } else if (e.key === 'ArrowRight') {
          e.preventDefault();
          setSelectedCandidateIdx((prev) => (prev + 1) % currentCandidates.length);
        } else if (e.key === 'ArrowLeft') {
          e.preventDefault();
          setSelectedCandidateIdx((prev) => (prev - 1 + currentCandidates.length) % currentCandidates.length);
        } else if (e.key === 'PageDown') {
          e.preventDefault();
          if (page < totalPages) setPage((p) => p + 1);
        } else if (e.key === 'PageUp') {
          e.preventDefault();
          if (page > 1) setPage((p) => p - 1);
        } else if (e.key === 'Backspace') {
          if (pinyinInput.length > 0) {
            setPinyinInput((prev) => prev.slice(0, -1));
          }
        }
      }
    };

    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [pinyinInput, currentCandidates, selectedCandidateIdx, page, totalPages]);

  const handleSelectCandidate = (candidate: CandidateItem) => {
    setNotepadText((prev) => prev + candidate.text);
    setPinyinInput('');
    setPage(1);
    setSelectedCandidateIdx(0);
  };

  const handleCheckUpdate = () => {
    alert('GY输入法 v2.5.0 目前已是最新稳定版本 (Build 20260801)。');
  };

  const handleToggleTheme = () => {
    onUpdateSettings((prev) => ({
      ...prev,
      appearance: {
        ...prev.appearance,
        theme: prev.appearance.theme === 'dark' ? 'light' : 'dark',
      },
    }));
  };

  return (
    <div className={`min-h-screen w-full flex flex-col font-sans transition-colors duration-300 ${
      isDark ? 'bg-slate-950 text-slate-100' : 'bg-slate-100 text-slate-900'
    }`}>
      {/* Top Prototype Controls Banner */}
      <header className={`px-4 py-2.5 border-b backdrop-blur-md flex items-center justify-between z-30 ${
        isDark ? 'bg-slate-900/90 border-slate-800' : 'bg-white/90 border-slate-200'
      }`}>
        <div className="flex items-center gap-3">
          <div className="w-10 h-7 flex items-center justify-center" title="GY 输入法">
            <GYBrandLogo height={22} color={isDark ? '#F8FAFC' : '#111318'} />
          </div>
          <div>
            <div className="font-bold text-sm leading-none flex items-center gap-1.5">
              <span>{settings.about.appName}</span>
              <span className="text-[10px] px-1.5 py-0.2 rounded bg-blue-100 dark:bg-blue-950 text-blue-700 dark:text-blue-300 font-mono">
                高保真交互原型
              </span>
            </div>
            <p className="text-[10px] text-slate-400 mt-0.5">母品牌：{settings.about.brand} • Windows 11/10 独立全套界面展示</p>
          </div>
        </div>

        {/* Quick Trigger Preset Buttons */}
        <div className="flex items-center gap-2 overflow-x-auto text-xs font-medium">
          <button
            onClick={() => setPinyinInput('gyshurufa')}
            className={`px-3 py-1.5 rounded-lg border transition-all flex items-center gap-1.5 ${
              pinyinInput === 'gyshurufa'
                ? 'bg-blue-600 text-white border-blue-600 shadow-xs'
                : isDark ? 'bg-slate-800 border-slate-700 hover:bg-slate-700' : 'bg-slate-50 border-slate-300 hover:bg-slate-100'
            }`}
          >
            <span>输入候选窗</span>
            <span className="font-mono text-[10px] opacity-80">(gyshurufa)</span>
          </button>

          <button
            onClick={() => setShowTrayMenu((prev) => !prev)}
            className={`px-3 py-1.5 rounded-lg border transition-all flex items-center gap-1.5 ${
              showTrayMenu
                ? 'bg-blue-600 text-white border-blue-600 shadow-xs'
                : isDark ? 'bg-slate-800 border-slate-700 hover:bg-slate-700' : 'bg-slate-50 border-slate-300 hover:bg-slate-100'
            }`}
          >
            <Sliders className="w-3.5 h-3.5 text-blue-500" />
            <span>托盘菜单</span>
          </button>

          <button
            onClick={() => setShowAiPanel(true)}
            className="px-3 py-1.5 rounded-lg bg-blue-50 dark:bg-blue-950/80 text-blue-700 dark:text-blue-300 border border-blue-200 dark:border-blue-800 hover:bg-blue-100 transition-all flex items-center gap-1.5"
          >
            <Sparkles className="w-3.5 h-3.5 text-blue-600" />
            <span>AI 助手面板</span>
          </button>

          <button
            onClick={() => {
              setSettingsTab('general');
              setShowSettingsModal(true);
            }}
            className="px-3 py-1.5 rounded-lg border border-slate-300 dark:border-slate-700 hover:bg-slate-200 dark:hover:bg-slate-800 transition-colors flex items-center gap-1.5"
          >
            <Sliders className="w-3.5 h-3.5" />
            <span>设置中心</span>
          </button>

          <button
            onClick={() => setShowOnboarding(true)}
            className="px-3 py-1.5 rounded-lg border border-slate-300 dark:border-slate-700 hover:bg-slate-200 dark:hover:bg-slate-800 transition-colors flex items-center gap-1.5"
          >
            <HelpCircle className="w-3.5 h-3.5" />
            <span>新用户引导</span>
          </button>

          <div className="h-4 w-px bg-slate-300 dark:bg-slate-800 mx-1" />

          <button
            onClick={handleToggleTheme}
            className={`p-1.5 rounded-lg border transition-colors ${
              isDark ? 'bg-slate-800 border-slate-700 text-amber-400' : 'bg-slate-50 border-slate-300 text-slate-700'
            }`}
            title="切换浅色 / 深色主题"
          >
            {isDark ? <Sun className="w-4 h-4" /> : <Moon className="w-4 h-4" />}
          </button>
        </div>
      </header>

      {/* Main Desktop Canvas Workspace */}
      <main className="flex-1 relative overflow-hidden flex flex-col justify-between p-6 bg-gradient-to-br from-slate-200 via-slate-100 to-slate-300 dark:from-slate-950 dark:via-slate-900 dark:to-slate-950">
        
        {/* Desktop App Window Container */}
        <div className="max-w-4xl w-full mx-auto my-auto shadow-2xl rounded-2xl border overflow-hidden backdrop-blur-md transition-all duration-200 z-10 flex flex-col h-[520px] bg-white/95 dark:bg-slate-900/95 border-slate-200/80 dark:border-slate-800">
          
          {/* Windows Titlebar */}
          <div className={`px-4 py-2.5 border-b flex items-center justify-between select-none ${
            isDark ? 'border-slate-800 bg-slate-950/80 text-slate-300' : 'border-slate-200 bg-slate-100/80 text-slate-700'
          }`}>
            <div className="flex items-center gap-3">
              <div className="flex items-center gap-1.5">
                <button
                  onClick={() => setActiveTab('notepad')}
                  className={`px-3 py-1 rounded-lg text-xs font-medium transition-all flex items-center gap-1.5 ${
                    activeTab === 'notepad'
                      ? 'bg-white dark:bg-slate-800 text-blue-700 dark:text-blue-300 shadow-xs border border-slate-200 dark:border-slate-700 font-semibold'
                      : 'hover:bg-slate-200/60 dark:hover:bg-slate-800/60 text-slate-600 dark:text-slate-400'
                  }`}
                >
                  <FileText className="w-3.5 h-3.5" />
                  <span>记事本 (输入候选体验)</span>
                </button>

                <button
                  onClick={() => setActiveTab('doc')}
                  className={`px-3 py-1 rounded-lg text-xs font-medium transition-all flex items-center gap-1.5 ${
                    activeTab === 'doc'
                      ? 'bg-white dark:bg-slate-800 text-blue-700 dark:text-blue-300 shadow-xs border border-slate-200 dark:border-slate-700 font-semibold'
                      : 'hover:bg-slate-200/60 dark:hover:bg-slate-800/60 text-slate-600 dark:text-slate-400'
                  }`}
                >
                  <Sparkles className="w-3.5 h-3.5" />
                  <span>文本编辑器 (AI 功能测试)</span>
                </button>
              </div>
            </div>

            <div className="flex items-center gap-2">
              <span className="text-[11px] text-slate-400 font-mono">
                输入法状态：{settings.general.defaultLanguage === 'zh' ? '中文 (全拼)' : 'English'}
              </span>
            </div>
          </div>

          {/* Window Body View 1: Interactive Notepad */}
          {activeTab === 'notepad' && (
            <div className="flex-1 p-6 flex flex-col justify-between relative space-y-4">
              <div className="space-y-2">
                <div className="flex items-center justify-between text-xs text-slate-500">
                  <span className="font-medium">在下方直接按键盘体验真实 GY 拼音选词输入：</span>
                  <div className="flex items-center gap-2">
                    <span className="text-[11px] font-mono bg-blue-50 dark:bg-blue-950 text-blue-600 dark:text-blue-400 px-2 py-0.5 rounded border border-blue-200 dark:border-blue-900">
                      提示：键盘输入字母自动唤出候选窗，数字1-9选词，空格确定首选
                    </span>
                  </div>
                </div>

                <div className="relative border rounded-xl p-4 bg-slate-50 dark:bg-slate-950/60 border-slate-200 dark:border-slate-800 h-[260px] overflow-y-auto">
                  <p className="whitespace-pre-wrap text-sm leading-relaxed font-sans text-slate-800 dark:text-slate-200">
                    {notepadText}
                    {pinyinInput && (
                      <span className="inline-flex items-center text-blue-600 dark:text-blue-400 bg-blue-50 dark:bg-blue-950/80 font-mono px-1 rounded underline font-semibold border border-blue-300 dark:border-blue-800 ml-1">
                        {pinyinInput}
                        <span className="w-0.5 h-4 bg-blue-600 animate-pulse ml-0.5" />
                      </span>
                    )}
                  </p>

                  {/* Floating Candidate Window positioning demo near text */}
                  {pinyinInput && (
                    <div className="mt-3 relative z-30 animate-in fade-in slide-in-from-top-1 duration-150">
                      <CandidateWindow
                        pinyin={pinyinInput}
                        candidates={currentCandidates}
                        selectedIndex={selectedCandidateIdx}
                        page={page}
                        totalPages={totalPages}
                        settings={settings}
                        onSelectCandidate={handleSelectCandidate}
                        onPrevPage={() => page > 1 && setPage(page - 1)}
                        onNextPage={() => page < totalPages && setPage(page + 1)}
                        onToggleAiPanel={() => setShowAiPanel(true)}
                        onToggleInputMode={() =>
                          onUpdateSettings((prev) => ({
                            ...prev,
                            general: {
                              ...prev.general,
                              defaultLanguage: prev.general.defaultLanguage === 'zh' ? 'en' : 'zh',
                            },
                          }))
                        }
                        isExpanded={candidateWindowExpanded}
                        onToggleExpand={() => setCandidateWindowExpanded(!candidateWindowExpanded)}
                      />
                    </div>
                  )}
                </div>
              </div>

              {/* Simulation Quick Pinyin Buttons */}
              <div className="flex items-center gap-2 text-xs text-slate-500 overflow-x-auto pb-1">
                <span className="shrink-0">一键试打拼音:</span>
                {['gyshurufa', 'gsyen', 'shurufa', 'pingyin', 'bendi', 'anquan', 'ai'].map((p) => (
                  <button
                    key={p}
                    onClick={() => setPinyinInput(p)}
                    className="px-2.5 py-1 rounded bg-slate-200/80 dark:bg-slate-800 text-slate-700 dark:text-slate-300 hover:bg-blue-600 hover:text-white font-mono text-xs transition-colors shrink-0"
                  >
                    {p}
                  </button>
                ))}
              </div>
            </div>
          )}

          {/* Window Body View 2: Document Editor for AI Polish/Translate testing */}
          {activeTab === 'doc' && (
            <div className="flex-1 p-6 flex flex-col justify-between space-y-4">
              <div className="space-y-2">
                <div className="flex items-center justify-between text-xs text-slate-500">
                  <span className="font-medium">选中段落体验 AI 润色 / 重写 / 翻译功能：</span>
                  <button
                    onClick={() => setShowAiPanel(true)}
                    className="px-3 py-1.5 rounded-lg bg-blue-600 hover:bg-blue-700 text-white font-medium text-xs shadow-md transition-all flex items-center gap-1.5"
                  >
                    <Sparkles className="w-3.5 h-3.5" />
                    <span>唤起 GY AI 助手 (Ctrl+Shift+A)</span>
                  </button>
                </div>

                <textarea
                  value={docText}
                  onChange={(e) => setDocText(e.target.value)}
                  rows={8}
                  className="w-full p-4 text-sm rounded-xl border outline-none font-sans leading-relaxed resize-none bg-slate-50 dark:bg-slate-950/60 border-slate-200 dark:border-slate-800 text-slate-800 dark:text-slate-200 focus:border-blue-500"
                />
              </div>

              <div className="p-3 rounded-xl bg-blue-50 dark:bg-blue-950/40 border border-blue-200 dark:border-blue-900 text-xs text-blue-800 dark:text-blue-300 flex items-center justify-between">
                <span>🔒 AI 助手仅在您主动按下快捷键或点击按钮时触发，绝不在后台自动读取当前文档。</span>
                <span className="font-mono text-[11px] opacity-80">隐私保护模式已开启</span>
              </div>
            </div>
          )}
        </div>

        {/* Windows Taskbar Bottom Bar */}
        <div className={`fixed bottom-0 left-0 right-0 h-12 border-t backdrop-blur-xl flex items-center justify-between px-4 z-40 ${
          isDark ? 'bg-slate-900/90 border-slate-800 text-slate-200' : 'bg-white/90 border-slate-200 text-slate-800'
        }`}>
          {/* Start button and taskbar icons */}
          <div className="flex items-center gap-2">
            <button
              onClick={() => setShowOnboarding(true)}
              className="w-8 h-8 rounded-lg hover:bg-slate-200 dark:hover:bg-slate-800 flex items-center justify-center transition-colors"
              title="Windows 开始菜单 / 新用户引导"
            >
              <Layout className="w-4 h-4 text-blue-600" />
            </button>

            <button
              onClick={() => setActiveTab('notepad')}
              className={`px-2.5 py-1.5 rounded-lg text-xs font-medium transition-colors flex items-center gap-1.5 ${
                activeTab === 'notepad' ? 'bg-slate-200 dark:bg-slate-800 text-blue-600 font-semibold' : 'hover:bg-slate-100 dark:hover:bg-slate-800'
              }`}
            >
              <FileText className="w-3.5 h-3.5" />
              <span>记事本</span>
            </button>

            <button
              onClick={() => setShowAiPanel(true)}
              className="px-2.5 py-1.5 rounded-lg text-xs font-medium hover:bg-slate-100 dark:hover:bg-slate-800 transition-colors flex items-center gap-1.5 text-blue-600 dark:text-blue-400"
            >
              <Sparkles className="w-3.5 h-3.5" />
              <span>GY AI 助手</span>
            </button>

            <button
              onClick={() => {
                setSettingsTab('general');
                setShowSettingsModal(true);
              }}
              className="px-2.5 py-1.5 rounded-lg text-xs font-medium hover:bg-slate-100 dark:hover:bg-slate-800 transition-colors flex items-center gap-1.5"
            >
              <Sliders className="w-3.5 h-3.5" />
              <span>设置</span>
            </button>
          </div>

          {/* Right System Tray */}
          <div className="flex items-center gap-2">
            {/* GY Input Method Tray Indicator Badge */}
            <button
              onClick={() => setShowTrayMenu((prev) => !prev)}
              className={`flex items-center gap-1.5 px-2.5 py-1 rounded-lg border text-xs font-medium transition-all ${
                showTrayMenu
                  ? 'bg-blue-600 text-white border-blue-600 shadow-md'
                  : isDark
                  ? 'bg-slate-800 border-slate-700 hover:bg-slate-700 text-slate-200'
                  : 'bg-slate-100 border-slate-300 hover:bg-slate-200 text-slate-800'
              }`}
              title="GY输入法托盘状态 (点击打开托盘菜单)"
            >
              <div className="w-6 h-4 flex items-center justify-center">
                <GYBrandLogo height={14} color={showTrayMenu || isDark ? '#F8FAFC' : '#111318'} />
              </div>
              <span>{settings.general.defaultLanguage === 'zh' ? '中' : '英'}</span>
              <span className="text-[10px] opacity-75">{settings.input.pinyinType === 'quanpin' ? '全' : '双'}</span>
              <ShieldCheck className="w-3 h-3 text-emerald-500" />
            </button>

            {/* Time / Date */}
            <div className="text-right text-[11px] font-mono leading-tight px-2 text-slate-500 dark:text-slate-400 border-l border-slate-200 dark:border-slate-800">
              <div>12:00</div>
              <div>2026/08/01</div>
            </div>
          </div>
        </div>

        {/* System Tray Popover Menu */}
        <TrayMenu
          settings={settings}
          isOpen={showTrayMenu}
          onClose={() => setShowTrayMenu(false)}
          onOpenSettings={(tab) => {
            if (tab) setSettingsTab(tab);
            setShowSettingsModal(true);
          }}
          onUpdateSettings={onUpdateSettings}
          onCheckUpdate={handleCheckUpdate}
          onToggleTheme={handleToggleTheme}
        />

        {/* AI Assistant Panel Modal */}
        <AiAssistantPanel
          isOpen={showAiPanel}
          initialText={selectedDocText || docText}
          settings={settings}
          onClose={() => setShowAiPanel(false)}
          onApplyResult={(newText) => {
            if (activeTab === 'doc') {
              setDocText(newText);
            } else {
              setNotepadText(newText);
            }
          }}
        />

        {/* Full Settings Modal */}
        {showSettingsModal && (
          <SettingsLayout
            settings={settings}
            activeTab={settingsTab}
            onClose={() => setShowSettingsModal(false)}
            onUpdateSettings={onUpdateSettings}
            onCheckUpdate={handleCheckUpdate}
          />
        )}

        {/* Onboarding Wizard Modal */}
        <OnboardingModal
          isOpen={showOnboarding}
          settings={settings}
          onClose={() => setShowOnboarding(false)}
          onFinish={() => setShowOnboarding(false)}
        />
      </main>
    </div>
  );
};
