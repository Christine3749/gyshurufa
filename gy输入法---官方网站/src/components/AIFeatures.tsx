import React, { useState } from 'react';
import { Sparkles, Languages, FileText, Zap, Workflow, ArrowRight, Check, Key, ShieldAlert } from 'lucide-react';
import { AI_FEATURES } from '../data/content';

export const AIFeatures: React.FC = () => {
  const [selectedFeatureId, setSelectedFeatureId] = useState('polish');
  const [customText, setCustomText] = useState('');
  const [isProcessing, setIsProcessing] = useState(false);
  const [processedOutput, setProcessedOutput] = useState<string | null>(null);

  const activeFeature = AI_FEATURES.find((f) => f.id === selectedFeatureId) || AI_FEATURES[0];

  const handleSimulateAiTrigger = () => {
    setIsProcessing(true);
    setProcessedOutput(null);

    setTimeout(() => {
      setIsProcessing(false);
      if (customText.trim()) {
        if (selectedFeatureId === 'polish') {
          setProcessedOutput(`【润色结果】${customText} ➔ 表达更严谨专业：${customText}已进行精细化优化，语句通顺且体裁得体。`);
        } else if (selectedFeatureId === 'translate') {
          setProcessedOutput(`【即时英文翻译】" ${customText} " ➔ " Refined English: ${customText} (Translated seamlessly via GSYEN AI) "`);
        } else if (selectedFeatureId === 'summarize') {
          setProcessedOutput(`【核心摘要提炼】1. 核心诉求：${customText.slice(0, 20)}... 2. 结论：需进行后续跟进确认。`);
        } else if (selectedFeatureId === 'snippets') {
          setProcessedOutput(`【快捷扩展展开】${customText} ➔ [模版结果]: 针对该指令自动生成对应的标准化段落。`);
        } else {
          setProcessedOutput(`【GSYEN 工作流触发】已将文本："${customText}" 自动同步至 GSYEN Workspace 待办任务卡片中。`);
        }
      } else {
        setProcessedOutput(activeFeature.exampleProcessed);
      }
    }, 600);
  };

  const getIcon = (iconName: string) => {
    switch (iconName) {
      case 'Sparkles': return <Sparkles className="w-5 h-5 text-blue-600" />;
      case 'Languages': return <Languages className="w-5 h-5 text-indigo-600" />;
      case 'FileText': return <FileText className="w-5 h-5 text-sky-600" />;
      case 'Zap': return <Zap className="w-5 h-5 text-amber-500" />;
      case 'Workflow': return <Workflow className="w-5 h-5 text-blue-600" />;
      default: return <Sparkles className="w-5 h-5 text-blue-600" />;
    }
  };

  return (
    <section id="ai-features" className="py-24 bg-slate-50 relative overflow-hidden">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        
        {/* Header */}
        <div className="text-center max-w-3xl mx-auto space-y-4 mb-16">
          <div className="inline-flex items-center gap-2 px-3.5 py-1.5 rounded-full bg-blue-50 text-blue-700 text-xs font-semibold border border-blue-200/60">
            <Sparkles className="w-3.5 h-3.5 text-blue-600" />
            克制的 AI 增强功能
          </div>
          <h2 className="text-3xl sm:text-4xl font-extrabold text-slate-900 tracking-tight">
            需要时，AI 才出现。
          </h2>
          <p className="text-slate-600 text-base leading-relaxed">
            没有无休止的常驻弹窗，没有强制的网络上传。基础打字纯离线，AI 增强仅在您按下特定快捷键时，为您精准提供协助。
          </p>
        </div>

        {/* Feature Cards Grid */}
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6 mb-12">
          {AI_FEATURES.map((feat) => {
            const isSelected = selectedFeatureId === feat.id;
            return (
              <div
                key={feat.id}
                onClick={() => {
                  setSelectedFeatureId(feat.id);
                  setProcessedOutput(null);
                }}
                className={`p-6 rounded-2xl transition-all cursor-pointer border relative flex flex-col justify-between ${
                  isSelected
                    ? 'bg-white border-blue-600 shadow-xl ring-2 ring-blue-600/20'
                    : 'bg-white/80 hover:bg-white border-slate-200 hover:border-slate-300 shadow-xs'
                }`}
              >
                <div className="space-y-4">
                  <div className="flex items-center justify-between">
                    <div className="w-10 h-10 rounded-xl bg-slate-50 border border-slate-100 flex items-center justify-center">
                      {getIcon(feat.iconName)}
                    </div>
                    <span className="text-[11px] font-mono font-semibold px-2.5 py-1 rounded-full bg-slate-100 text-slate-700 border border-slate-200">
                      {feat.triggerKey}
                    </span>
                  </div>

                  <div className="space-y-1">
                    <h3 className="text-lg font-bold text-slate-900">{feat.title}</h3>
                    <p className="text-xs text-blue-600 font-medium">{feat.subtitle}</p>
                    <p className="text-xs text-slate-500 pt-1 leading-relaxed">{feat.description}</p>
                  </div>
                </div>

                <div className="pt-4 mt-4 border-t border-slate-100 flex items-center justify-between text-xs text-slate-400">
                  <span>标签: {feat.tag}</span>
                  <span className={`font-semibold flex items-center gap-1 ${isSelected ? 'text-blue-600' : 'text-slate-400'}`}>
                    {isSelected ? '正在体验中' : '点击试用'}
                    <ArrowRight className="w-3.5 h-3.5" />
                  </span>
                </div>
              </div>
            );
          })}
        </div>

        {/* Interactive AI Playground Sandbox */}
        <div className="bg-slate-900 text-slate-100 rounded-3xl p-6 sm:p-10 shadow-2xl border border-slate-800 space-y-6">
          <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 border-b border-slate-800 pb-5">
            <div>
              <div className="flex items-center gap-2">
                <Sparkles className="w-5 h-5 text-blue-400" />
                <h3 className="text-lg font-bold text-white">
                  实时沙盒体验：{activeFeature.title}
                </h3>
              </div>
              <p className="text-xs text-slate-400 mt-1">
                触发快捷键：<strong className="text-blue-400 font-mono">{activeFeature.triggerKey}</strong>
              </p>
            </div>

            <div className="flex items-center gap-2">
              <span className="text-xs text-emerald-400 bg-emerald-950/80 px-3 py-1 rounded-full border border-emerald-800/60 font-mono">
                🔒 默认禁用上传 · 仅本次点击触发
              </span>
            </div>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
            {/* Input Side */}
            <div className="space-y-3">
              <label className="text-xs font-semibold text-slate-400 block">
                【待处理原文本】(可使用示例或自行输入)
              </label>
              <textarea
                value={customText}
                onChange={(e) => setCustomText(e.target.value)}
                placeholder={`示例：${activeFeature.exampleOriginal}`}
                rows={4}
                className="w-full p-4 rounded-xl bg-slate-800/90 border border-slate-700 text-slate-100 text-xs sm:text-sm focus:outline-none focus:border-blue-500 placeholder-slate-500 font-mono"
              />
              <div className="flex items-center justify-between">
                <button
                  onClick={() => setCustomText(activeFeature.exampleOriginal)}
                  className="text-xs text-slate-400 hover:text-slate-200 underline"
                >
                  填入预设文案
                </button>
                <button
                  onClick={handleSimulateAiTrigger}
                  disabled={isProcessing}
                  className="px-5 py-2.5 rounded-xl bg-blue-600 hover:bg-blue-500 text-white font-medium text-xs sm:text-sm transition-all shadow-md shadow-blue-600/30 flex items-center gap-2"
                >
                  {isProcessing ? (
                    <>
                      <div className="w-3.5 h-3.5 border-2 border-white border-t-transparent rounded-full animate-spin" />
                      AI 正在处理...
                    </>
                  ) : (
                    <>
                      <Sparkles className="w-4 h-4" />
                      模拟触发 {activeFeature.triggerKey}
                    </>
                  )}
                </button>
              </div>
            </div>

            {/* Output Side */}
            <div className="space-y-3">
              <label className="text-xs font-semibold text-slate-400 block">
                【候选框原位替换结果】
              </label>
              <div className="p-4 rounded-xl bg-slate-850/90 border border-slate-800 min-h-[110px] text-xs sm:text-sm text-slate-200 font-mono flex items-center justify-center text-center">
                {isProcessing ? (
                  <span className="text-blue-400 animate-pulse">正在加密传输给 GSYEN AI 节点进行推理...</span>
                ) : processedOutput ? (
                  <div className="text-left text-emerald-300 w-full space-y-2 animate-fadeIn">
                    <p className="leading-relaxed">{processedOutput}</p>
                    <div className="text-[10px] text-slate-400 border-t border-slate-800 pt-2 flex items-center justify-between">
                      <span>快捷操作：按 Enter 原位覆盖</span>
                      <span>按 Esc 撤销替换</span>
                    </div>
                  </div>
                ) : (
                  <span className="text-slate-500">点击左侧“模拟触发”按钮查看 AI 原位替换效果</span>
                )}
              </div>
            </div>
          </div>

          {/* Privacy Commitment Disclaimer Notice */}
          <div className="p-4 rounded-xl bg-slate-800/50 border border-slate-700/80 text-xs text-slate-300 flex items-start gap-3">
            <ShieldAlert className="w-5 h-5 text-amber-400 shrink-0 mt-0.5" />
            <div className="leading-relaxed">
              <span className="font-bold text-white">隐私隔离严格承诺：</span>
              GY输入法绝不默认后台悄悄上传您的输入内容。所有的 AI 请求均为<strong>一次性显式调用</strong>，推理完成后立即断开网络握手，零服务器沉淀日志，您可以随时在设置中一键彻底关停所有 AI 模组。
            </div>
          </div>
        </div>

      </div>
    </section>
  );
};
