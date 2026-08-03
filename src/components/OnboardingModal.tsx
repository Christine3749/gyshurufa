import React, { useState } from 'react';
import { Zap, ShieldCheck, Sparkles, ArrowRight, Check, X } from 'lucide-react';
import { UserSettings } from '../types';
import { GYBrandLogo } from './GYBrandLogo';

interface OnboardingModalProps {
  isOpen: boolean;
  settings: UserSettings;
  onClose: () => void;
  onFinish: () => void;
}

export const OnboardingModal: React.FC<OnboardingModalProps> = ({
  isOpen,
  settings,
  onClose,
  onFinish,
}) => {
  const [step, setStep] = useState<1 | 2 | 3>(1);

  if (!isOpen) return null;

  const isDark = settings.appearance.theme === 'dark';

  return (
    <div className="fixed inset-0 bg-black/50 backdrop-blur-xs z-50 flex items-center justify-center p-4 animate-in fade-in duration-200">
      <div
        className={`
          w-full max-w-lg rounded-3xl shadow-2xl border overflow-hidden transition-all duration-200
          ${
            isDark
              ? 'bg-slate-900 border-slate-700/80 text-slate-100 shadow-slate-950/90'
              : 'bg-white border-slate-200/90 text-slate-800 shadow-slate-400/30'
          }
        `}
      >
        {/* Top bar with progress dots */}
        <div className="px-6 pt-6 flex items-center justify-between">
          <div className="flex items-center gap-2">
            {[1, 2, 3].map((s) => (
              <div
                key={s}
                className={`h-1.5 rounded-full transition-all duration-300 ${
                  s === step
                    ? 'w-8 bg-blue-600'
                    : s < step
                    ? 'w-3 bg-blue-400'
                    : 'w-3 bg-slate-200 dark:bg-slate-800'
                }`}
              />
            ))}
          </div>

          <button
            onClick={onClose}
            className={`p-1 rounded-xl transition-colors text-slate-400 ${
              isDark ? 'hover:bg-slate-800' : 'hover:bg-slate-100'
            }`}
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        {/* Step Content */}
        <div className="p-8 text-center space-y-6">
          {step === 1 && (
            <div className="space-y-4 animate-in fade-in zoom-in-95 duration-200">
              <div className="h-20 flex items-center justify-center mx-auto" title="GY 输入法">
                <GYBrandLogo height={62} color={isDark ? '#F8FAFC' : '#111318'} />
              </div>
              <div className="space-y-1">
                <h2 className="text-2xl font-bold tracking-tight">欢迎使用 GY输入法</h2>
                <p className="text-xs text-blue-600 dark:text-blue-400 font-mono">GSYEN 旗下快、准、本地优先的中文输入系统</p>
              </div>
              <p className="text-sm text-slate-500 dark:text-slate-400 leading-relaxed max-w-sm mx-auto">
                轻量原生的 Windows 打字体验。无广告弹窗、不偷占 CPU，为您提供顺滑、高清晰度的汉字选词与编辑。
              </p>
              <div className="grid grid-cols-3 gap-2 text-xs pt-2 font-medium">
                <div className="p-2.5 rounded-xl bg-blue-50 dark:bg-blue-950/40 text-blue-800 dark:text-blue-300 border border-blue-200/60 dark:border-blue-900/50">
                  ⚡ 极速打字
                </div>
                <div className="p-2.5 rounded-xl bg-blue-50 dark:bg-blue-950/40 text-blue-800 dark:text-blue-300 border border-blue-200/60 dark:border-blue-900/50">
                  🎯 高准词库
                </div>
                <div className="p-2.5 rounded-xl bg-blue-50 dark:bg-blue-950/40 text-blue-800 dark:text-blue-300 border border-blue-200/60 dark:border-blue-900/50">
                  🎨 磨砂美学
                </div>
              </div>
            </div>
          )}

          {step === 2 && (
            <div className="space-y-4 animate-in fade-in zoom-in-95 duration-200">
              <div className="w-20 h-20 rounded-3xl bg-emerald-600 text-white flex items-center justify-center mx-auto shadow-xl">
                <ShieldCheck className="w-10 h-10" />
              </div>
              <div className="space-y-1">
                <h2 className="text-2xl font-bold tracking-tight">本地优先，输入更安心</h2>
                <p className="text-xs text-emerald-600 dark:text-emerald-400 font-mono">零隐秘上传 • 词库完全属于你</p>
              </div>
              <p className="text-sm text-slate-500 dark:text-slate-400 leading-relaxed max-w-sm mx-auto">
                基础输入与自造词库全部在您的 Windows 设备本地进行处理与保存。无需登录云端账号，绝不窥探个人隐私。
              </p>
              <div className="p-3 rounded-2xl bg-emerald-500/10 text-emerald-800 dark:text-emerald-300 text-xs font-medium border border-emerald-200 dark:border-emerald-900 text-left space-y-1">
                <div className="flex items-center gap-1.5 font-bold">
                  <Check className="w-4 h-4 text-emerald-600" />
                  <span>隐私合规保证</span>
                </div>
                <p className="text-[11px] text-slate-600 dark:text-slate-400 leading-normal">
                  您可随时在【设置中心 ➔ 隐私】一键导出或清空全部本地学习数据。
                </p>
              </div>
            </div>
          )}

          {step === 3 && (
            <div className="space-y-4 animate-in fade-in zoom-in-95 duration-200">
              <div className="w-20 h-20 rounded-3xl bg-blue-600 text-white flex items-center justify-center mx-auto shadow-xl">
                <Sparkles className="w-10 h-10" />
              </div>
              <div className="space-y-1">
                <h2 className="text-2xl font-bold tracking-tight">AI 功能由你决定何时开启</h2>
                <p className="text-xs text-blue-600 dark:text-blue-400 font-mono">绝不后台自动抓取文字</p>
              </div>
              <p className="text-sm text-slate-500 dark:text-slate-400 leading-relaxed max-w-sm mx-auto">
                AI 助手只会在您主动点击“AI”按钮或按下快捷键 <code className="px-1.5 py-0.5 rounded bg-slate-200 dark:bg-slate-800 font-mono text-xs">Ctrl+Shift+A</code> 时启动，协助您润色、重写或翻译。
              </p>
              <div className="p-3 rounded-2xl bg-blue-500/10 text-blue-900 dark:text-blue-200 text-xs text-left border border-blue-200 dark:border-blue-900 font-medium">
                💡 提示：您亦可在托盘菜单或设置中随时选择完全关闭 AI 功能。
              </div>
            </div>
          )}
        </div>

        {/* Bottom Actions */}
        <div
          className={`px-8 py-5 border-t flex items-center justify-between ${
            isDark ? 'border-slate-800 bg-slate-950/60' : 'border-slate-100 bg-slate-50'
          }`}
        >
          {step > 1 ? (
            <button
              onClick={() => setStep((s) => (s - 1) as any)}
              className={`px-4 py-2 rounded-xl text-xs font-medium transition-colors ${
                isDark ? 'hover:bg-slate-800 text-slate-300' : 'hover:bg-slate-200 text-slate-700'
              }`}
            >
              上一步
            </button>
          ) : (
            <div />
          )}

          {step < 3 ? (
            <button
              onClick={() => setStep((s) => (s + 1) as any)}
              className="px-6 py-2.5 rounded-xl bg-blue-600 hover:bg-blue-700 text-white font-medium text-xs shadow-md transition-all flex items-center gap-1.5"
            >
              <span>下一步</span>
              <ArrowRight className="w-4 h-4" />
            </button>
          ) : (
            <button
              onClick={() => {
                onFinish();
                onClose();
              }}
              className="px-8 py-2.5 rounded-xl bg-blue-600 hover:bg-blue-700 text-white font-bold text-xs shadow-lg hover:shadow-blue-500/25 transition-all flex items-center gap-2"
            >
              <Check className="w-4 h-4" />
              <span>开始输入</span>
            </button>
          )}
        </div>
      </div>
    </div>
  );
};
