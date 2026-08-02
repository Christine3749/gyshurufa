import React from 'react';
import { X, History, Sparkles, CheckCircle, Tag } from 'lucide-react';
import { CHANGELOG_HISTORY } from '../../data/content';

interface ChangelogModalProps {
  isOpen: boolean;
  onClose: () => void;
}

export const ChangelogModal: React.FC<ChangelogModalProps> = ({ isOpen, onClose }) => {
  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-900/60 backdrop-blur-sm animate-fadeIn">
      <div 
        className="relative w-full max-w-2xl max-h-[85vh] bg-white rounded-2xl shadow-2xl border border-slate-100 overflow-hidden flex flex-col text-slate-800"
        onClick={(e) => e.stopPropagation()}
      >
        {/* Header */}
        <div className="flex items-center justify-between px-6 py-5 border-b border-slate-100 bg-slate-50/80 shrink-0">
          <div className="flex items-center space-x-3">
            <div className="w-10 h-10 rounded-xl bg-blue-50 text-blue-600 border border-blue-200 flex items-center justify-center">
              <History className="w-5 h-5" />
            </div>
            <div>
              <h3 className="text-lg font-bold text-slate-900">GY输入法 版本更新日志</h3>
              <p className="text-xs text-slate-500">每一次演进，都离更完美的输入更近一步</p>
            </div>
          </div>
          <button
            onClick={onClose}
            className="p-2 rounded-lg text-slate-400 hover:text-slate-600 hover:bg-slate-100 transition-colors"
            aria-label="关闭窗口"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        {/* Timeline Content */}
        <div className="p-6 overflow-y-auto space-y-6 text-sm">
          {CHANGELOG_HISTORY.map((ver, idx) => (
            <div key={ver.version} className="relative pl-6 border-l-2 border-slate-100 space-y-3">
              <div className="absolute -left-[9px] top-1 w-4 h-4 rounded-full bg-blue-600 ring-4 ring-blue-50 flex items-center justify-center">
                <div className="w-1.5 h-1.5 rounded-full bg-white" />
              </div>

              <div className="flex flex-wrap items-center justify-between gap-2">
                <div className="flex items-center gap-2">
                  <span className="font-bold text-base text-slate-900">{ver.version}</span>
                  <span className="text-xs px-2 py-0.5 rounded-full bg-blue-50 text-blue-700 font-medium border border-blue-200">
                    {ver.channel}
                  </span>
                </div>
                <span className="text-xs text-slate-400 font-mono">{ver.date}</span>
              </div>

              <ul className="space-y-2 text-xs sm:text-sm text-slate-600">
                {ver.highlights.map((item, i) => (
                  <li key={i} className="flex items-start gap-2">
                    <CheckCircle className="w-4 h-4 text-emerald-600 shrink-0 mt-0.5" />
                    <span>{item}</span>
                  </li>
                ))}
              </ul>

              <div className="p-2.5 rounded-lg bg-slate-50 text-[11px] font-mono text-slate-500 break-all border border-slate-100">
                <span className="text-slate-400 font-semibold">SHA256: </span>{ver.sha256}
              </div>
            </div>
          ))}
        </div>

        {/* Footer */}
        <div className="px-6 py-4 bg-slate-50 border-t border-slate-100 flex items-center justify-between shrink-0 text-xs text-slate-500">
          <span>完整升级机制支持 Windows 自动静默下载提示</span>
          <button
            onClick={onClose}
            className="px-5 py-2 rounded-xl bg-slate-900 hover:bg-slate-800 text-white font-medium text-xs sm:text-sm transition-all"
          >
            关闭
          </button>
        </div>
      </div>
    </div>
  );
};
