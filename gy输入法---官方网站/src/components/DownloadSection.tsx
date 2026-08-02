import React, { useState } from 'react';
import { Download, ShieldCheck, Laptop, Check, Copy, FileText, ChevronRight, History } from 'lucide-react';
import { BRAND_INFO } from '../data/content';

interface DownloadSectionProps {
  onOpenDownloadModal: () => void;
  onOpenChangelogModal: () => void;
}

export const DownloadSection: React.FC<DownloadSectionProps> = ({
  onOpenDownloadModal,
  onOpenChangelogModal
}) => {
  const [copiedHash, setCopiedHash] = useState(false);

  const handleCopyHash = () => {
    navigator.clipboard.writeText(BRAND_INFO.sha256);
    setCopiedHash(true);
    setTimeout(() => setCopiedHash(false), 2000);
  };

  return (
    <section id="download" className="py-24 bg-slate-50 relative overflow-hidden">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 relative z-10">
        
        {/* Main Banner Card */}
        <div className="bg-white rounded-3xl p-8 sm:p-12 border border-slate-200/80 shadow-xl max-w-4xl mx-auto text-center space-y-8">
          
          {/* Badge */}
          <div className="inline-flex items-center gap-2 px-3.5 py-1.5 rounded-full bg-blue-50 text-blue-700 text-xs font-semibold border border-blue-200/60">
            <Laptop className="w-4 h-4 text-blue-600" />
            首发 Windows 10 / 11 平台
          </div>

          {/* Heading */}
          <div className="space-y-3">
            <h2 className="text-3xl sm:text-4xl font-extrabold text-slate-900 tracking-tight">
              从 Windows 开始。
            </h2>
            <p className="text-slate-600 text-base max-w-xl mx-auto leading-relaxed">
              立即体验快、准、默认本地优先的 AI 原生中文输入法。开启更纯粹、更流畅的打字之旅。
            </p>
          </div>

          {/* Download Primary Action Button */}
          <div className="pt-2 flex flex-col sm:flex-row items-center justify-center gap-4">
            <button
              onClick={onOpenDownloadModal}
              className="w-full sm:w-auto inline-flex items-center justify-center px-8 py-4 rounded-2xl bg-blue-600 hover:bg-blue-700 active:bg-blue-800 text-white font-bold text-lg shadow-xl shadow-blue-600/20 transition-all gap-3 active:scale-98 group"
            >
              <Download className="w-5 h-5 group-hover:translate-y-0.5 transition-transform" />
              下载 GY输入法 for Windows
            </button>

            <button
              onClick={onOpenChangelogModal}
              className="w-full sm:w-auto inline-flex items-center justify-center px-6 py-4 rounded-2xl bg-slate-100 hover:bg-slate-200/80 text-slate-700 font-medium text-sm transition-all gap-2"
            >
              <History className="w-4 h-4 text-slate-500" />
              更新日志 ({BRAND_INFO.version})
            </button>
          </div>

          {/* Platform Note */}
          <p className="text-xs text-slate-500">
            支持 Windows 10 (21H2 或更高版本) 与 Windows 11 (22H2/23H2)。当前为早期预览版。
          </p>

          {/* Version Specs Grid */}
          <div className="pt-6 border-t border-slate-100 grid grid-cols-2 sm:grid-cols-4 gap-4 text-left text-xs">
            <div className="p-3.5 rounded-xl bg-slate-50 border border-slate-100 space-y-0.5">
              <span className="text-slate-400 block">版本号</span>
              <span className="font-bold text-slate-800 font-mono text-sm">{BRAND_INFO.version}</span>
            </div>

            <div className="p-3.5 rounded-xl bg-slate-50 border border-slate-100 space-y-0.5">
              <span className="text-slate-400 block">发布日期</span>
              <span className="font-bold text-slate-800 font-mono text-sm">{BRAND_INFO.releaseDate}</span>
            </div>

            <div className="p-3.5 rounded-xl bg-slate-50 border border-slate-100 space-y-0.5">
              <span className="text-slate-400 block">文件大小</span>
              <span className="font-bold text-slate-800 font-mono text-sm">{BRAND_INFO.fileSize}</span>
            </div>

            <div className="p-3.5 rounded-xl bg-slate-50 border border-slate-100 space-y-0.5">
              <span className="text-slate-400 block">系统架构</span>
              <span className="font-bold text-slate-800 font-mono text-sm">{BRAND_INFO.architecture}</span>
            </div>
          </div>

          {/* SHA256 Verification Quick Bar */}
          <div className="p-3.5 rounded-xl bg-slate-900 text-slate-300 text-xs flex flex-col sm:flex-row items-center justify-between gap-3 text-left">
            <div className="flex items-center gap-2 overflow-hidden w-full sm:w-auto">
              <ShieldCheck className="w-4 h-4 text-blue-400 shrink-0" />
              <span className="text-slate-400 shrink-0 font-medium">SHA-256:</span>
              <span className="font-mono text-[11px] truncate text-slate-200">{BRAND_INFO.sha256}</span>
            </div>

            <button
              onClick={handleCopyHash}
              className="text-xs text-blue-400 hover:text-blue-300 font-medium shrink-0 flex items-center gap-1 bg-slate-800 px-3 py-1.5 rounded-lg border border-slate-700"
            >
              {copiedHash ? (
                <>
                  <Check className="w-3.5 h-3.5 text-emerald-400" />
                  已复制
                </>
              ) : (
                <>
                  <Copy className="w-3.5 h-3.5" />
                  复制完整校验码
                </>
              )}
            </button>
          </div>

        </div>

      </div>
    </section>
  );
};
