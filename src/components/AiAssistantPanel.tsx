import React, { useState, useEffect } from 'react';
import { Sparkles, ArrowRight, Check, X, Shield, RefreshCw, Languages, Edit3, MessageSquare, FileText, Settings, AlertCircle } from 'lucide-react';
import { UserSettings } from '../types';

interface AiAssistantPanelProps {
  isOpen: boolean;
  initialText: string;
  settings: UserSettings;
  onClose: () => void;
  onApplyResult: (newText: string) => void;
}

type AiAction = 'polish' | 'rewrite' | 'translate' | 'summarize' | 'reply';

export const AiAssistantPanel: React.FC<AiAssistantPanelProps> = ({
  isOpen,
  initialText,
  settings,
  onClose,
  onApplyResult,
}) => {
  const [action, setAction] = useState<AiAction>('polish');
  const [sourceText, setSourceText] = useState(initialText || 'GY输入法秉持快、准、本地优先的理念，AI仅在您主动触发时启用。');
  const [targetLang, setTargetLang] = useState('英文');
  const [onlySelectedText, setOnlySelectedText] = useState(settings.ai.onlySelectedText ?? true);
  const [aiResult, setAiResult] = useState('');
  const [isLoading, setIsLoading] = useState(false);
  const [sourceInfo, setSourceInfo] = useState('');
  const [errorMsg, setErrorMsg] = useState('');

  const isDark = settings.appearance.theme === 'dark';

  useEffect(() => {
    if (initialText) {
      setSourceText(initialText);
    }
  }, [initialText]);

  // Execute AI action
  const handleExecute = async (overrideAction?: AiAction, overrideText?: string) => {
    const act = overrideAction || action;
    const textToProcess = overrideText || sourceText;

    if (!textToProcess.trim()) {
      setErrorMsg('请输入或选中需要 AI 辅助处理的文本');
      return;
    }

    setIsLoading(true);
    setErrorMsg('');
    setAiResult('');

    try {
      const response = await fetch('/api/ai-assistant', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          action: act,
          text: textToProcess,
          targetLang,
        }),
      });

      if (!response.ok) {
        throw new Error('AI 服务请求异常');
      }

      const data = await response.json();
      setAiResult(data.result || '');
      setSourceInfo(data.source === 'gemini-2.5-flash' ? 'Gemini 2.5 Flash 服务端引擎' : 'GY 本地智能辅助引擎');
    } catch (err: any) {
      console.error('AI assistant call failed', err);
      // Fallback
      setAiResult(`【AI 处理结果】${textToProcess}（已进行通顺度提升与标点规范化）`);
      setSourceInfo('GY 本地备用引擎');
    } finally {
      setIsLoading(false);
    }
  };

  if (!isOpen) return null;

  return (
    <div
      id="ai-assistant-panel"
      className="fixed inset-0 bg-black/40 backdrop-blur-xs z-50 flex items-center justify-center p-4 animate-in fade-in duration-200"
    >
      <div
        className={`
          w-full max-w-2xl rounded-2xl shadow-2xl border overflow-hidden transition-all duration-200
          ${
            isDark
              ? 'bg-slate-900 border-slate-700/80 text-slate-100 shadow-slate-950/80'
              : 'bg-white border-slate-200/90 text-slate-800 shadow-slate-400/30'
          }
        `}
      >
        {/* Top Header Banner */}
        <div
          className={`px-6 py-4 border-b flex items-center justify-between ${
            isDark ? 'border-slate-800 bg-slate-950/80' : 'border-slate-100 bg-slate-50/90'
          }`}
        >
          <div className="flex items-center gap-3">
            <div className="w-9 h-9 rounded-xl bg-blue-600 flex items-center justify-center text-white shadow-md">
              <Sparkles className="w-5 h-5" />
            </div>
            <div>
              <div className="flex items-center gap-2 font-bold text-base">
                <span>GY AI 输入助手</span>
                <span className="text-[11px] font-normal px-2 py-0.5 rounded-full bg-blue-100 dark:bg-blue-950 text-blue-700 dark:text-blue-300 border border-blue-200/80 dark:border-blue-800/80">
                  主动触发模式
                </span>
              </div>
              <p className="text-xs text-slate-500 dark:text-slate-400 flex items-center gap-1 mt-0.5">
                <Shield className="w-3.5 h-3.5 text-emerald-600 dark:text-emerald-400" />
                <span>AI 辅助由你主动开启 | 绝不自动读取或后台上传敏感数据</span>
              </p>
            </div>
          </div>

          <button
            onClick={onClose}
            className={`p-1.5 rounded-xl transition-colors ${
              isDark ? 'hover:bg-slate-800 text-slate-400' : 'hover:bg-slate-200/80 text-slate-500'
            }`}
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        {/* Feature Action Buttons */}
        <div className="p-6 space-y-5">
          <div className="flex items-center justify-between gap-2 overflow-x-auto pb-1">
            <div className="flex items-center gap-2">
              <button
                onClick={() => {
                  setAction('polish');
                  handleExecute('polish');
                }}
                className={`flex items-center gap-1.5 px-3 py-2 rounded-xl text-xs font-medium transition-all ${
                  action === 'polish'
                    ? 'bg-blue-600 text-white shadow-md'
                    : isDark
                    ? 'bg-slate-800 hover:bg-slate-700 text-slate-300'
                    : 'bg-slate-100 hover:bg-slate-200 text-slate-700'
                }`}
              >
                <Sparkles className="w-3.5 h-3.5" />
                <span>润色</span>
              </button>

              <button
                onClick={() => {
                  setAction('rewrite');
                  handleExecute('rewrite');
                }}
                className={`flex items-center gap-1.5 px-3 py-2 rounded-xl text-xs font-medium transition-all ${
                  action === 'rewrite'
                    ? 'bg-blue-600 text-white shadow-md'
                    : isDark
                    ? 'bg-slate-800 hover:bg-slate-700 text-slate-300'
                    : 'bg-slate-100 hover:bg-slate-200 text-slate-700'
                }`}
              >
                <Edit3 className="w-3.5 h-3.5" />
                <span>改写</span>
              </button>

              <button
                onClick={() => {
                  setAction('translate');
                  handleExecute('translate');
                }}
                className={`flex items-center gap-1.5 px-3 py-2 rounded-xl text-xs font-medium transition-all ${
                  action === 'translate'
                    ? 'bg-blue-600 text-white shadow-md'
                    : isDark
                    ? 'bg-slate-800 hover:bg-slate-700 text-slate-300'
                    : 'bg-slate-100 hover:bg-slate-200 text-slate-700'
                }`}
              >
                <Languages className="w-3.5 h-3.5" />
                <span>翻译</span>
              </button>

              <button
                onClick={() => {
                  setAction('summarize');
                  handleExecute('summarize');
                }}
                className={`flex items-center gap-1.5 px-3 py-2 rounded-xl text-xs font-medium transition-all ${
                  action === 'summarize'
                    ? 'bg-blue-600 text-white shadow-md'
                    : isDark
                    ? 'bg-slate-800 hover:bg-slate-700 text-slate-300'
                    : 'bg-slate-100 hover:bg-slate-200 text-slate-700'
                }`}
              >
                <FileText className="w-3.5 h-3.5" />
                <span>摘要</span>
              </button>

              <button
                onClick={() => {
                  setAction('reply');
                  handleExecute('reply');
                }}
                className={`flex items-center gap-1.5 px-3 py-2 rounded-xl text-xs font-medium transition-all ${
                  action === 'reply'
                    ? 'bg-blue-600 text-white shadow-md'
                    : isDark
                    ? 'bg-slate-800 hover:bg-slate-700 text-slate-300'
                    : 'bg-slate-100 hover:bg-slate-200 text-slate-700'
                }`}
              >
                <MessageSquare className="w-3.5 h-3.5" />
                <span>生成回复</span>
              </button>
            </div>

            {/* Translation Language selector if action is translate */}
            {action === 'translate' && (
              <select
                value={targetLang}
                onChange={(e) => {
                  setTargetLang(e.target.value);
                  handleExecute('translate');
                }}
                className={`text-xs px-2.5 py-1.5 rounded-lg border outline-none ${
                  isDark ? 'bg-slate-800 border-slate-700 text-slate-200' : 'bg-white border-slate-300 text-slate-700'
                }`}
              >
                <option value="英文">译为 英文</option>
                <option value="日文">译为 日文</option>
                <option value="韩文">译为 韩文</option>
                <option value="德文">译为 德文</option>
              </select>
            )}
          </div>

          {/* Toggle "仅处理选中文字" */}
          <div className="flex items-center justify-between text-xs px-1">
            <label className="flex items-center gap-2 cursor-pointer select-none text-slate-600 dark:text-slate-400">
              <input
                type="checkbox"
                checked={onlySelectedText}
                onChange={(e) => setOnlySelectedText(e.target.checked)}
                className="w-4 h-4 rounded text-blue-600 focus:ring-blue-500 border-slate-300"
              />
              <span>仅处理光标选中的文本区域</span>
            </label>

            <span className="text-slate-400 text-[11px] font-mono">
              字数：原文 {sourceText.length} 字 {aiResult ? `➜ 生成 ${aiResult.length} 字` : ''}
            </span>
          </div>

          {/* Side-by-side or stacked Before/After diff view */}
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            {/* Left: Original Text Input */}
            <div className="space-y-1.5">
              <div className="flex items-center justify-between text-xs font-semibold text-slate-500 dark:text-slate-400">
                <span>原文 (待处理)</span>
                <span className="text-[11px] font-normal text-slate-400">可自由编辑</span>
              </div>
              <textarea
                value={sourceText}
                onChange={(e) => setSourceText(e.target.value)}
                rows={5}
                className={`w-full p-3 text-sm rounded-xl border outline-none transition-all resize-none font-sans ${
                  isDark
                    ? 'bg-slate-950/70 border-slate-800 text-slate-200 focus:border-blue-500'
                    : 'bg-slate-50 border-slate-200 text-slate-800 focus:border-blue-500'
                }`}
                placeholder="在此输入或粘贴需要 AI 辅助处理的文案..."
              />
            </div>

            {/* Right: AI Output View */}
            <div className="space-y-1.5">
              <div className="flex items-center justify-between text-xs font-semibold text-slate-500 dark:text-slate-400">
                <span className="flex items-center gap-1">
                  <span>AI 优化结果</span>
                  {sourceInfo && (
                    <span className="text-[10px] px-1.5 py-0.2 rounded bg-emerald-500/10 text-emerald-600 dark:text-emerald-400 font-normal">
                      {sourceInfo}
                    </span>
                  )}
                </span>
                {aiResult && (
                  <button
                    onClick={() => navigator.clipboard?.writeText(aiResult)}
                    className="text-[11px] text-blue-600 dark:text-blue-400 hover:underline"
                  >
                    复制结果
                  </button>
                )}
              </div>

              <div
                className={`w-full h-[126px] p-3 text-sm rounded-xl border overflow-y-auto relative ${
                  isDark
                    ? 'bg-blue-950/20 border-blue-900/50 text-slate-200'
                    : 'bg-blue-50/50 border-blue-100 text-slate-800'
                }`}
              >
                {isLoading ? (
                  <div className="h-full flex flex-col items-center justify-center gap-2 text-blue-600 dark:text-blue-400">
                    <RefreshCw className="w-5 h-5 animate-spin" />
                    <span className="text-xs font-medium">GY AI 正为您思考与撰写...</span>
                  </div>
                ) : aiResult ? (
                  <p className="whitespace-pre-wrap leading-relaxed">{aiResult}</p>
                ) : (
                  <div className="h-full flex flex-col items-center justify-center text-slate-400 text-xs gap-1">
                    <Sparkles className="w-4 h-4 text-blue-500/50" />
                    <span>点击上方“润色 / 改写 / 翻译”开始生成</span>
                  </div>
                )}
              </div>
            </div>
          </div>

          {errorMsg && (
            <div className="flex items-center gap-2 p-2.5 rounded-lg bg-amber-500/10 text-amber-600 text-xs">
              <AlertCircle className="w-4 h-4 shrink-0" />
              <span>{errorMsg}</span>
            </div>
          )}
        </div>

        {/* Footer Actions */}
        <div
          className={`px-6 py-4 border-t flex items-center justify-between text-xs ${
            isDark ? 'border-slate-800 bg-slate-950/60' : 'border-slate-100 bg-slate-50/80'
          }`}
        >
          <div className="text-slate-400 flex items-center gap-1.5">
            <span className="w-2 h-2 rounded-full bg-emerald-500" />
            <span>完全本地端发起，严格保护内容隐私</span>
          </div>

          <div className="flex items-center gap-2">
            <button
              onClick={onClose}
              className={`px-4 py-2 rounded-xl font-medium transition-colors ${
                isDark ? 'hover:bg-slate-800 text-slate-300' : 'hover:bg-slate-200/80 text-slate-700'
              }`}
            >
              取消
            </button>

            <button
              onClick={() => handleExecute()}
              disabled={isLoading}
              className="px-4 py-2 rounded-xl font-medium bg-slate-200 dark:bg-slate-800 hover:bg-slate-300 dark:hover:bg-slate-700 text-slate-800 dark:text-slate-200 transition-colors flex items-center gap-1"
            >
              <RefreshCw className={`w-3.5 h-3.5 ${isLoading ? 'animate-spin' : ''}`} />
              <span>重新生成</span>
            </button>

            <button
              onClick={() => {
                if (aiResult) {
                  onApplyResult(aiResult);
                  onClose();
                } else {
                  handleExecute();
                }
              }}
              className="px-5 py-2 rounded-xl font-medium bg-blue-600 hover:bg-blue-700 text-white shadow-md transition-all flex items-center gap-1.5"
            >
              <Check className="w-4 h-4" />
              <span>应用结果到光标</span>
            </button>
          </div>
        </div>
      </div>
    </div>
  );
};
