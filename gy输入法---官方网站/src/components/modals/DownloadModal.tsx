import React, { useState } from 'react';
import { X, Download, ShieldCheck, Check, Copy, Laptop, FileText, ExternalLink } from 'lucide-react';
import { BRAND_INFO } from '../../data/content';
import { formatReleaseBytes, formatReleaseDate, useReleaseStatus } from '../../hooks/useReleaseStatus';
import { useUserPlatform } from '../../hooks/useUserPlatform';

interface DownloadModalProps {
  isOpen: boolean;
  onClose: () => void;
}

export const DownloadModal: React.FC<DownloadModalProps> = ({ isOpen, onClose }) => {
  const [copiedHash, setCopiedHash] = useState(false);
  const [downloadStarted, setDownloadStarted] = useState(false);
  const { release, loading } = useReleaseStatus();
  // 平台感知：Mac 访客看到的是 Mac 包的地址与校验，不再是 Windows 包。
  const platform = useUserPlatform();
  const isMac = platform === 'macos';
  const windows = release?.platforms.windows;
  const macos = release?.platforms.macos;
  const current = isMac ? macos : windows;
  const ready = Boolean(current?.available);

  if (!isOpen) return null;

  const handleCopyHash = () => {
    if (!ready) return;
    navigator.clipboard.writeText(current.sha256);
    setCopiedHash(true);
    setTimeout(() => setCopiedHash(false), 2000);
  };

  const handleTriggerDownload = () => {
    if (!ready || !current?.downloadUrl) return;
    setDownloadStarted(true);
    window.location.assign(current.downloadUrl);
  };

  const title = isMac ? 'GY输入法 for Mac' : 'GY输入法 for Windows';
  const subtitle = isMac
    ? '官方预览安装包 · macOS · Apple Silicon (M1 / M2 / M3 / M4)'
    : '官方预览安装包 · Windows 10 / 11 (64-bit)';
  const osRequirement = isMac
    ? 'macOS 13 (Ventura) 或更高版本\nApple Silicon 芯片（M1 及更新）'
    : 'Windows 11 (22H2 / 23H2)\nWindows 10 (21H2 或更高版本)';

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
                {title}
                <span className="text-xs font-semibold px-2 py-0.5 rounded-full bg-blue-50 text-blue-700 border border-blue-200">
                  {current ? `v${current.version}` : loading ? '读取中' : '验证中'}
                </span>
              </h3>
              <p className="text-xs text-slate-500">{subtitle}</p>
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
                <p className="text-sm font-semibold text-slate-900">{current?.filename ?? '安装包验证中'}</p>
                <div className="flex items-center gap-3 text-xs text-slate-500 mt-1">
                  <span>文件大小：{formatReleaseBytes(current?.bytes)}</span>
                  <span>•</span>
                  <span>更新日期：{formatReleaseDate(release?.publishedAtUtc)}</span>
                </div>
              </div>

              <button
                onClick={handleTriggerDownload}
                disabled={!ready}
                className="inline-flex items-center justify-center px-5 py-3 rounded-xl bg-blue-600 hover:bg-blue-700 active:bg-blue-800 disabled:bg-slate-300 disabled:shadow-none disabled:cursor-not-allowed text-white font-medium text-sm transition-all shadow-lg shadow-blue-600/20 gap-2 shrink-0"
              >
                <Download className="w-4 h-4" />
                {ready ? (downloadStarted ? '重新下载' : '立即免费下载') : '安装包验证中'}
              </button>
            </div>

            {!current && (
              <div className="p-3 rounded-lg bg-amber-50 text-amber-800 border border-amber-200/60 text-xs">
                当前没有可验证的{isMac ? ' macOS ' : ' Windows '}安装包。为避免混装，下载入口会保持关闭。
              </div>
            )}
            {downloadStarted && (
              <div className="p-3 rounded-lg bg-emerald-50 text-emerald-800 border border-emerald-200/60 text-xs flex items-center gap-2 animate-fadeIn">
                <Check className="w-4 h-4 text-emerald-600 shrink-0" />
                <span>下载已触发。请仅从 shurufa.wang 下载，并在安装前核对下方 SHA-256。</span>
              </div>
            )}
          </div>

          {/* SHA256 Verification & Security */}
          <div className="space-y-3">
            <div className="flex items-center justify-between">
              <span className="text-xs font-semibold text-slate-700 flex items-center gap-1.5">
                <ShieldCheck className="w-4 h-4 text-blue-600" />
                安装包完整性校验 (SHA-256)
              </span>
              <button
                onClick={handleCopyHash}
                disabled={!ready}
                className="text-xs text-blue-600 hover:text-blue-700 font-medium flex items-center gap-1"
              >
                {copiedHash ? (
                  <>
                    <Check className="w-4 h-4 text-emerald-600" />
                    已复制哈希值
                  </>
                ) : (
                  <>
                    <Copy className="w-4 h-4" />
                    复制完整哈希
                  </>
                )}
              </button>
            </div>
            <div className="p-3 rounded-lg bg-slate-900 text-slate-300 font-mono text-xs break-all leading-relaxed select-all">
              {ready ? (current?.sha256 || '发布验证中') : '待校验' }
            </div>
          </div>

          {/* System Requirements Grid */}
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 text-xs">
            <div className="p-3 rounded-lg border border-slate-100 bg-slate-50/50 flex items-start gap-2.5">
              <Laptop className="w-4 h-4 text-slate-500 mt-0.5 shrink-0" />
              <div>
                <p className="font-semibold text-slate-800">操作系统支持</p>
                {osRequirement.split('\n').map((line) => (
                  <p key={line} className="text-slate-500 mt-0.5">{line}</p>
                ))}
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
