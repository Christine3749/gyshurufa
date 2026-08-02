import React, { useState } from 'react';
import { X, Download, ShieldCheck, Check, Copy, Laptop, FileText, ExternalLink } from 'lucide-react';
import { BRAND_INFO } from '../../data/content';

interface DownloadModalProps {
  isOpen: boolean;
  onClose: () => void;
}

export const DownloadModal: React.FC<DownloadModalProps> = ({ isOpen, onClose }) => {
  const [copiedHash, setCopiedHash] = useState(false);
  const [downloadStarted, setDownloadStarted] = useState(false);

  if (!isOpen) return null;

  const handleCopyHash = () => {
    navigator.clipboard.writeText(BRAND_INFO.sha256);
    setCopiedHash(true);
    setTimeout(() => setCopiedHash(false), 2000);
  };

  const handleTriggerDownload = () => {
    setDownloadStarted(true);
    window.location.assign(BRAND_INFO.downloadUrl);
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-900/60 backdrop-blur-sm animate-fadeIn">
      <div 
        className="relative w-full max-w-2xl bg-white rounded-2xl shadow-2xl border border-slate-100 overflow-hidden text-slate-800"
        onClick={(e) => e.stopPropagation()}
      >
        {/* Header Bar */}
        <div className="flex items-center justify-between px-6 py-5 border-b border-slate-100 bg-slate-50/50">
          <div className="flex items-center space-x-3">
            <div className="w-10 h-10 rounded-xl bg-blue-600 flex items-center justify-center text-white font-bold text-lg shadow-md shadow-blue-500/20">
              GY
            </div>
            <div>
              <h3 className="text-lg font-bold text-slate-900 flex items-center gap-2">
                GY输入法 for Windows
                <span className="text-xs font-semibold px-2 py-0.5 rounded-full bg-blue-50 text-blue-700 border border-blue-200">
                  {BRAND_INFO.version}
                </span>
              </h3>
              <p className="text-xs text-slate-500">官方安装包 · Windows 10 / 11 (64-bit)</p>
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

        {/* Content Body */}
        <div className="p-6 space-y-6">
          {/* Download Box */}
          <div className="p-5 rounded-xl bg-slate-50 border border-slate-200/80 space-y-4">
            <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
              <div>
                <p className="text-sm font-semibold text-slate-900">GYShurufa_Setup_x64.exe</p>
                <div className="flex items-center gap-3 text-xs text-slate-500 mt-1">
                  <span>文件大小：{BRAND_INFO.fileSize}</span>
                  <span>•</span>
                  <span>更新日期：{BRAND_INFO.releaseDate}</span>
                </div>
              </div>

              <button
                onClick={handleTriggerDownload}
                className="inline-flex items-center justify-center px-5 py-3 rounded-xl bg-blue-600 hover:bg-blue-700 active:bg-blue-800 text-white font-medium text-sm transition-all shadow-lg shadow-blue-600/20 gap-2 shrink-0"
              >
                <Download className="w-4 h-4" />
                {downloadStarted ? '重新下载' : '立即免费下载'}
              </button>
            </div>

            {downloadStarted && (
              <div className="p-3 rounded-lg bg-emerald-50 text-emerald-800 border border-emerald-200/60 text-xs flex items-center gap-2 animate-fadeIn">
                <Check className="w-4 h-4 text-emerald-600 shrink-0" />
                <span>下载已触发！如提示安全警告，请选择“保留”或“信任发布者 GSYEN”。</span>
              </div>
            )}
          </div>

          {/* SHA256 Verification & Security */}
          <div className="space-y-3">
            <div className="flex items-center justify-between">
              <span className="text-xs font-semibold text-slate-700 flex items-center gap-1.5">
                <ShieldCheck className="w-4 h-4 text-blue-600" />
                安装包安全签名校验 (SHA-256)
              </span>
              <button
                onClick={handleCopyHash}
                className="text-xs text-blue-600 hover:text-blue-700 font-medium flex items-center gap-1"
              >
                {copiedHash ? (
                  <>
                    <Check className="w-3.5 h-3.5 text-emerald-600" />
                    已复制哈希值
                  </>
                ) : (
                  <>
                    <Copy className="w-3.5 h-3.5" />
                    复制完整哈希
                  </>
                )}
              </button>
            </div>
            <div className="p-3 rounded-lg bg-slate-900 text-slate-300 font-mono text-xs break-all leading-relaxed select-all">
              {BRAND_INFO.sha256}
            </div>
          </div>

          {/* System Requirements Grid */}
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 text-xs">
            <div className="p-3 rounded-lg border border-slate-100 bg-slate-50/50 flex items-start gap-2.5">
              <Laptop className="w-4 h-4 text-slate-500 mt-0.5 shrink-0" />
              <div>
                <p className="font-semibold text-slate-800">操作系统支持</p>
                <p className="text-slate-500 mt-0.5">Windows 11 (22H2 / 23H2)<br />Windows 10 (21H2 或更高版本)</p>
              </div>
            </div>
            <div className="p-3 rounded-lg border border-slate-100 bg-slate-50/50 flex items-start gap-2.5">
              <FileText className="w-4 h-4 text-slate-500 mt-0.5 shrink-0" />
              <div>
                <p className="font-semibold text-slate-800">硬件推荐要求</p>
                <p className="text-slate-500 mt-0.5">内存：最少 512MB 可用内存<br />硬盘：至少 100MB 空间</p>
              </div>
            </div>
          </div>

          {/* Privacy Note */}
          <div className="p-3 rounded-lg bg-blue-50/60 border border-blue-100 text-xs text-blue-900 leading-relaxed">
            <span className="font-semibold">纯净与承诺：</span>
            GY输入法安装包不含任何第三方静默捆绑软件、无广告弹窗插件。默认纯离线模式运行，保障所有打字数据严格保留在您的电脑本地。
          </div>
        </div>

        {/* Footer */}
        <div className="px-6 py-4 bg-slate-50 border-t border-slate-100 flex items-center justify-between text-xs text-slate-500">
          <span>官方域名: {BRAND_INFO.domain}</span>
          <a 
            href="#privacy" 
            onClick={onClose}
            className="text-slate-600 hover:text-blue-600 transition-colors flex items-center gap-1"
          >
            阅读完整隐私白皮书 <ExternalLink className="w-3 h-3" />
          </a>
        </div>
      </div>
    </div>
  );
};
