import React, { useState, useEffect } from 'react';
import { Download, Shield, Sparkles, Check, ChevronRight, Zap, Command, RefreshCw, Terminal } from 'lucide-react';
import { BRAND_INFO, TYPING_SCENARIOS } from '../data/content';
import { useReleaseStatus } from '../hooks/useReleaseStatus';
import { useUserPlatform } from '../hooks/useUserPlatform';

interface HeroProps {
  onOpenDownload: () => void;
  onOpenPrivacy: () => void;
}

export const Hero: React.FC<HeroProps> = ({ onOpenDownload, onOpenPrivacy }) => {
  const [selectedScenarioIndex, setSelectedScenarioIndex] = useState(0);
  const [activeCandidateIndex, setActiveCandidateIndex] = useState(0);
  const [isAiActive, setIsAiActive] = useState(false);
  const [customInput, setCustomInput] = useState('');
  const [isTypingSimulated, setIsTypingSimulated] = useState(false);

  const scenario = TYPING_SCENARIOS[selectedScenarioIndex];

  // 按访客设备给主按钮：Mac 直接下 Apple Silicon 包，Windows 走校验弹窗。
  const platform = useUserPlatform();
  const { release } = useReleaseStatus();
  const macos = release?.platforms.macos;
  const macosReady = Boolean(macos?.available);
  const primaryLabel = platform === 'macos'
    ? '免费下载 Mac 版'
    : platform === 'windows'
      ? '免费下载 Windows 版'
      : '免费下载';
  const handlePrimaryDownload = () => {
    if (platform === 'macos' && macosReady && macos?.downloadUrl) {
      window.location.assign(macos.downloadUrl);
      return;
    }
    onOpenDownload();
  };

  // Auto cycling for typing demonstration if user isn't interacting
  useEffect(() => {
    if (customInput !== '') return;
    const interval = setInterval(() => {
      setSelectedScenarioIndex((prev) => (prev + 1) % TYPING_SCENARIOS.length);
      setActiveCandidateIndex(0);
      setIsAiActive(false);
    }, 6000);
    return () => clearInterval(interval);
  }, [customInput]);

  return (
    <section id="hero" className="relative pt-28 sm:pt-36 pb-20 overflow-hidden bg-slate-50/80">
      {/* Background Subtle Grid & Ambient Glow */}
      <div className="absolute inset-0 bg-[linear-gradient(to_right,#e2e8f0_1px,transparent_1px),linear-gradient(to_bottom,#e2e8f0_1px,transparent_1px)] bg-[size:4rem_4rem] [mask-image:radial-gradient(ellipse_60%_50%_at_50%_0%,#000_70%,transparent_100%)] opacity-40 pointer-events-none" />
      
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 relative z-10">
        <div className="grid grid-cols-1 lg:grid-cols-12 gap-12 lg:gap-8 items-center">
          
          {/* Left Column: Headline & Value Proposition */}
          <div className="lg:col-span-6 space-y-8 text-center lg:text-left">
            {/* Top Pill Badge */}
            <div className="inline-flex items-center gap-2 px-3.5 py-1.5 rounded-full bg-blue-50 border border-blue-200/80 text-blue-700 text-xs font-semibold shadow-xs animate-fadeIn">
              <span className="w-2 h-2 rounded-full bg-blue-600 animate-pulse" />
              面向 Windows 10/11 的 AI 原生中文输入法
              <span className="text-slate-400">|</span>
              <span className="text-slate-600 font-mono">shurufa.wang</span>
            </div>

            {/* Main Headline */}
            <div className="space-y-4">
              <h1 className="text-4xl sm:text-5xl lg:text-6xl font-extrabold text-slate-900 tracking-tight leading-[1.15]">
                GY输入法，<br />
                <span className="text-blue-600">AI时代的输入法。</span>
              </h1>
              <p className="text-base sm:text-lg text-slate-600 max-w-xl mx-auto lg:mx-0 leading-relaxed font-normal">
                GY输入法是一款面向 Windows 的 AI 原生中文输入法。毫秒级低延迟响应、精准拼音联想、默认本地优先。让 AI 在你明确需要时增强输入，而基础拼音、词库与学习始终默认本地优先。
              </p>
            </div>

            {/* Primary Action Buttons */}
            <div className="flex flex-col sm:flex-row items-center justify-center lg:justify-start gap-4 pt-2">
              <button
                onClick={handlePrimaryDownload}
                className="w-full sm:w-auto inline-flex items-center justify-center px-7 py-3.5 rounded-2xl bg-blue-600 hover:bg-blue-700 active:bg-blue-800 text-white font-semibold text-base transition-all shadow-xl shadow-blue-600/20 gap-2.5 group active:scale-98"
              >
                <Download className="w-5 h-5 group-hover:translate-y-0.5 transition-transform" />
                {primaryLabel}
              </button>

              <button
                onClick={onOpenPrivacy}
                className="w-full sm:w-auto inline-flex items-center justify-center px-6 py-3.5 rounded-2xl bg-white hover:bg-slate-100/80 text-slate-700 font-medium text-base border border-slate-200 transition-all shadow-xs gap-2"
              >
                <Shield className="w-4 h-4 text-blue-600" />
                了解隐私设计
              </button>
            </div>

            {/* Sub-badges & Feature Metrics */}
            <div className="pt-4 border-t border-slate-200/60 grid grid-cols-3 gap-4 text-center lg:text-left">
              <div>
                <p className="text-xl font-bold text-slate-900 font-mono">&lt; 0.8ms</p>
                <p className="text-xs text-slate-500 mt-0.5">本地首字响应</p>
              </div>
              <div>
                <p className="text-xl font-bold text-slate-900 font-mono">100%</p>
                <p className="text-xs text-slate-500 mt-0.5">基础输入纯离线</p>
              </div>
              <div>
                <p className="text-xl font-bold text-slate-900">GSYEN</p>
                <p className="text-xs text-slate-500 mt-0.5">原生工具生态</p>
              </div>
            </div>
          </div>

          {/* Right Column: Original Interactive Candidate Window Prototype */}
          <div className="lg:col-span-6">
            <div className="relative mx-auto max-w-lg lg:max-w-none">
              
              {/* Outer Decorative Card Frame */}
              <div className="p-6 sm:p-8 rounded-3xl bg-white/90 backdrop-blur-xl border border-slate-200/80 shadow-2xl shadow-slate-900/10 space-y-6">
                
                {/* Simulated Windows Top App Header */}
                <div className="flex items-center justify-between pb-4 border-b border-slate-100">
                  <div className="flex items-center gap-2">
                    <div className="w-3 h-3 rounded-full bg-slate-300" />
                    <div className="w-3 h-3 rounded-full bg-slate-300" />
                    <div className="w-3 h-3 rounded-full bg-slate-300" />
                    <span className="text-xs text-slate-400 font-mono ml-2">GY IME Candidate Window v1.2</span>
                  </div>

                  {/* Scenario Tabs Selector */}
                  <div className="flex items-center gap-1 bg-slate-100 p-1 rounded-lg">
                    {TYPING_SCENARIOS.map((sc, i) => (
                      <button
                        key={sc.id}
                        onClick={() => {
                          setSelectedScenarioIndex(i);
                          setActiveCandidateIndex(0);
                          setIsAiActive(false);
                          setCustomInput('');
                        }}
                        className={`px-2.5 py-1 rounded-md text-[11px] font-medium transition-all ${
                          selectedScenarioIndex === i && customInput === ''
                            ? 'bg-white text-blue-600 shadow-xs'
                            : 'text-slate-500 hover:text-slate-800'
                        }`}
                      >
                        {sc.label}
                      </button>
                    ))}
                  </div>
                </div>

                {/* Simulated Document Editor & Cursor Floating Input Bar */}
                <div className="space-y-3">
                  <div className="text-xs text-slate-400 flex items-center justify-between">
                    <span>编辑文档中 (预览光标位置)：</span>
                    <span className="text-[11px] text-emerald-600 font-mono bg-emerald-50 px-2 py-0.5 rounded border border-emerald-200/50">
                      ⚡ 本地计算中 &lt; 0.8ms
                    </span>
                  </div>

                  {/* Mock Text Line */}
                  <div className="p-4 rounded-xl bg-slate-50 border border-slate-200/80 font-mono text-sm text-slate-800 relative min-h-[52px] flex items-center flex-wrap gap-1">
                    <span className="text-slate-400">正在敲击:</span>
                    <span className="font-bold text-blue-600 bg-blue-50 px-2 py-0.5 rounded">
                      {customInput !== '' ? customInput : scenario.rawInputDisplay}
                    </span>
                    <span className="w-0.5 h-5 bg-blue-600 animate-pulse inline-block align-middle" />
                  </div>
                </div>

                {/* Candidate Window Original Visual Design */}
                <div className="p-4 rounded-2xl bg-slate-900 text-slate-100 shadow-xl border border-slate-800 space-y-3 relative overflow-hidden">
                  
                  {/* Candidate Header Bar */}
                  <div className="flex items-center justify-between border-b border-slate-800 pb-2 text-[11px] text-slate-400">
                    <div className="flex items-center gap-2">
                      <span className="font-mono text-blue-400 font-bold">GY拼音</span>
                      <span className="text-slate-500">|</span>
                      <span>编码: <strong className="text-slate-200">{customInput || scenario.pinyinInput}</strong></span>
                    </div>
                    <span className="px-1.5 py-0.5 rounded bg-slate-800 text-slate-300 text-[10px]">
                      Windows 11 TSF
                    </span>
                  </div>

                  {/* Candidates List */}
                  <div className="space-y-2">
                    {scenario.candidates.map((cand, idx) => {
                      const isSelected = activeCandidateIndex === idx;
                      return (
                        <div
                          key={cand.id}
                          onClick={() => setActiveCandidateIndex(idx)}
                          className={`p-2.5 rounded-xl transition-all cursor-pointer flex items-center justify-between ${
                            isSelected
                              ? 'bg-blue-600 text-white shadow-md shadow-blue-600/30'
                              : 'bg-slate-800/60 hover:bg-slate-800 text-slate-200'
                          }`}
                        >
                          <div className="flex items-center gap-3">
                            <span className={`w-5 h-5 rounded-md flex items-center justify-center font-mono text-xs font-bold ${
                              isSelected ? 'bg-white/20 text-white' : 'bg-slate-700 text-slate-400'
                            }`}>
                              {cand.id}
                            </span>
                            <span className="font-medium text-sm tracking-wide">
                              {cand.word}
                            </span>
                          </div>

                          {cand.tag && (
                            <span className={`text-[10px] px-2 py-0.5 rounded-full font-medium ${
                              isSelected ? 'bg-blue-700 text-blue-100' : 'bg-slate-700/80 text-slate-400'
                            }`}>
                              {cand.tag}
                            </span>
                          )}
                        </div>
                      );
                    })}
                  </div>

                  {/* AI Feature Trigger Bar inside Candidate Popup */}
                  {scenario.aiSuggestion && (
                    <div className="pt-2 border-t border-slate-800 space-y-2">
                      <div className="flex items-center justify-between">
                        <span className="text-[11px] text-slate-400 flex items-center gap-1">
                          <Sparkles className="w-3.5 h-3.5 text-blue-400" />
                          {scenario.aiSuggestion.title}
                        </span>

                        <button
                          onClick={() => setIsAiActive(!isAiActive)}
                          className={`px-2.5 py-1 rounded-lg text-xs font-medium transition-all flex items-center gap-1 ${
                            isAiActive
                              ? 'bg-blue-500 text-white'
                              : 'bg-slate-800 text-blue-400 hover:bg-slate-700'
                          }`}
                        >
                          {isAiActive ? '取消展示' : '点击试用 AI'}
                        </button>
                      </div>

                      {isAiActive && (
                        <div className="p-3 rounded-xl bg-blue-950/80 border border-blue-800/80 text-xs text-blue-100 space-y-1.5 animate-fadeIn">
                          <div className="text-[10px] text-blue-300/80 font-mono">
                            【原文】{scenario.aiSuggestion.original}
                          </div>
                          <div className="font-medium text-white flex items-start gap-1.5">
                            <Zap className="w-3.5 h-3.5 text-amber-400 shrink-0 mt-0.5" />
                            <span>{scenario.aiSuggestion.result}</span>
                          </div>
                          <div className="text-[10px] text-blue-300/60 pt-1 border-t border-blue-900">
                            提示: 该操作仅由用户主动触发，基础打字绝不上传服务器。
                          </div>
                        </div>
                      )}
                    </div>
                  )}

                  {/* Bottom Shortcuts Hints */}
                  <div className="flex items-center justify-between text-[10px] text-slate-500 pt-1">
                    <span>[空格] 确认选中</span>
                    <span>[Shift] 切换中英</span>
                    <span>[Alt+/] 主动触发 AI</span>
                  </div>
                </div>

                {/* Custom Typing Sandbox Bar */}
                <div className="p-3 rounded-xl bg-slate-100/80 border border-slate-200 flex items-center gap-2">
                  <Terminal className="w-4 h-4 text-slate-500 shrink-0" />
                  <input
                    type="text"
                    value={customInput}
                    onChange={(e) => setCustomInput(e.target.value.toLowerCase().replace(/[^a-z/]/g, ''))}
                    placeholder="在此亲自体验试打拼音 (例如: gyshurufa /riqi)"
                    className="w-full text-xs bg-transparent border-none outline-none text-slate-800 placeholder-slate-400 font-mono"
                  />
                  {customInput && (
                    <button
                      onClick={() => setCustomInput('')}
                      className="text-[10px] text-slate-400 hover:text-slate-600 font-medium px-2 py-0.5 bg-white rounded shadow-xs"
                    >
                      清空
                    </button>
                  )}
                </div>

              </div>

            </div>
          </div>

        </div>
      </div>
    </section>
  );
};
