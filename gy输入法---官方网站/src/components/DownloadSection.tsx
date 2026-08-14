import React, { useState } from 'react';
import { ArrowUpRight, Check, CircleAlert, Copy, Download, History, Laptop, ShieldCheck, Smartphone, Terminal } from 'lucide-react';
import { formatReleaseBytes, formatReleaseDate, useReleaseStatus } from '../hooks/useReleaseStatus';
import { useUserPlatform } from '../hooks/useUserPlatform';

interface DownloadSectionProps {
  onOpenDownloadModal: () => void;
  onOpenChangelogModal: () => void;
}

export const DownloadSection: React.FC<DownloadSectionProps> = ({
  onOpenDownloadModal,
  onOpenChangelogModal
}) => {
  const [copiedHash, setCopiedHash] = useState(false);
  const { release, loading } = useReleaseStatus();
  const platform = useUserPlatform();
  const stableWindows = release?.platforms.windows;
  const candidateWindows = release?.windowsCandidate;
  // The latest public candidate is presented first without rewriting the
  // separate stable latest pointer.
  const windows = candidateWindows?.available ? candidateWindows : stableWindows;
  const windowsIsCandidate = Boolean(candidateWindows?.available);
  const windowsReady = Boolean(windows?.available);
  const macos = release?.platforms.macos;
  const macosReady = Boolean(macos?.available);

  const handleCopyHash = () => {
    if (!windowsReady) return;
    navigator.clipboard.writeText(windows.sha256);
    setCopiedHash(true);
    setTimeout(() => setCopiedHash(false), 2000);
  };

  return (
    <section id="download" className="py-24 bg-slate-50 relative overflow-hidden">
      <div className="max-w-6xl mx-auto px-4 sm:px-6 lg:px-8 relative z-10">
        <div className="text-center max-w-2xl mx-auto mb-10 space-y-3">
          <div className="inline-flex items-center gap-2 px-3.5 py-1.5 rounded-full bg-blue-50 text-blue-700 text-xs font-semibold border border-blue-200/60">
            <Download className="w-4 h-4" />
            官方下载中心
          </div>
          <h2 className="text-3xl sm:text-4xl font-extrabold text-slate-900 tracking-tight">选择你的设备。</h2>
          <p className="text-slate-600 leading-relaxed">
            {loading
              ? '正在读取官方发布状态。'
              : windows
                ? windowsIsCandidate
                  ? `Windows ${windows.version} 公开公测中；稳定版 ${stableWindows?.version ?? '仍可用'} 保持独立，不会被候选版覆盖。`
                  : `Windows ${windows.version} 已完成发布校验；macOS 仅在签名、公证与哈希都通过后开放下载。`
                : '当前没有可验证的公开安装包；不会显示或提供未验证下载。'}
          </p>
        </div>

        <div className="grid md:grid-cols-2 xl:grid-cols-3 gap-5 items-stretch">
          <article className="bg-white rounded-3xl p-7 sm:p-8 border border-slate-200/90 shadow-xl shadow-slate-900/5 flex flex-col">
            <div className="flex items-start justify-between gap-4">
              <div className="w-12 h-12 rounded-2xl bg-blue-600 text-white grid place-items-center shadow-lg shadow-blue-600/20">
                <Laptop className="w-6 h-6" />
              </div>
              <div className="flex items-center gap-2">
                {platform === 'windows' && (
                  <span className="inline-flex items-center rounded-full bg-emerald-50 px-3 py-1 text-xs font-semibold text-emerald-700 border border-emerald-200">你的设备</span>
                )}
                <span className={`inline-flex items-center rounded-full px-3 py-1 text-xs font-semibold border ${windowsIsCandidate ? 'bg-amber-50 text-amber-800 border-amber-200' : 'bg-blue-50 text-blue-700 border-blue-100'}`}>{windowsReady ? windowsIsCandidate ? '公测候选' : '现可下载' : loading ? '读取中' : '验证中'}</span>
              </div>
            </div>
            <div className="mt-7 space-y-2">
              <h3 className="text-2xl font-bold text-slate-900">GY输入法 for Windows</h3>
              <p className="text-sm text-slate-500">Windows 10 / 11 · 64-bit · {windows ? `v${windows.version}` : '发布验证中'}{windowsIsCandidate ? ' · 公测候选' : ''}</p>
              <p className="text-sm text-slate-600 leading-relaxed">{windowsIsCandidate ? '测试中英混打、英文候选、纠错和候选窗新体验。稳定版仍可在下载弹窗中选择。' : '完整拼音输入、候选窗、简繁 EN 切换与本地学习，默认本地运行。'}</p>
            </div>
            <div className="mt-7 pt-6 border-t border-slate-100 grid grid-cols-3 gap-3 text-xs">
              <div><span className="block text-slate-400">安装包</span><span className="font-semibold text-slate-700">{formatReleaseBytes(windows?.bytes)}</span></div>
              <div><span className="block text-slate-400">架构</span><span className="font-semibold text-slate-700">{windows?.architecture ?? '验证中'}</span></div>
              <div><span className="block text-slate-400">更新</span><span className="font-semibold text-slate-700">{formatReleaseDate(release?.publishedAtUtc)}</span></div>
            </div>
            <div className="mt-7 flex flex-col sm:flex-row gap-3">
              <button
                type="button"
                disabled={!windowsReady}
                aria-disabled={!windowsReady}
                onClick={windowsReady ? onOpenDownloadModal : undefined}
                className={`flex-1 inline-flex items-center justify-center gap-2 rounded-2xl px-5 py-3.5 text-sm font-bold transition-all ${windowsReady ? 'bg-blue-600 hover:bg-blue-700 active:bg-blue-800 text-white shadow-lg shadow-blue-600/20 active:scale-[.98]' : 'bg-slate-100 text-slate-400 cursor-not-allowed'}`}
              >
                <Download className="w-4 h-4" /> {windowsReady ? windowsIsCandidate ? '下载 Windows 内测版' : '下载 Windows 稳定版' : 'Windows 包验证中'}
              </button>
              <button
                onClick={onOpenChangelogModal}
                className="inline-flex items-center justify-center gap-2 rounded-2xl bg-slate-100 hover:bg-slate-200 px-5 py-3.5 text-sm font-semibold text-slate-700 transition-all"
              >
                <History className="w-4 h-4" /> 更新日志
              </button>
            </div>
          </article>

          <article className="rounded-3xl p-7 sm:p-8 border border-slate-200 bg-gradient-to-br from-slate-950 to-slate-800 text-white shadow-xl shadow-slate-900/10 flex flex-col">
            <div className="flex items-start justify-between gap-4">
              <div className="w-12 h-12 rounded-2xl bg-white/10 border border-white/15 text-white grid place-items-center">
                <Laptop className="w-6 h-6" />
              </div>
              <div className="flex items-center gap-2">
                {platform === 'macos' && (
                  <span className="inline-flex items-center rounded-full bg-emerald-400/15 px-3 py-1 text-xs font-semibold text-emerald-300 border border-emerald-300/25">你的设备</span>
                )}
                <span className="inline-flex items-center rounded-full bg-white/10 px-3 py-1 text-xs font-semibold text-slate-200 border border-white/10">{macosReady ? '现可下载' : loading ? '读取中' : '验证中'}</span>
              </div>
            </div>
            <div className="mt-7 space-y-2">
              <h3 className="text-2xl font-bold">GY输入法 for Mac</h3>
              <p className="text-sm text-slate-300">macOS · Apple Silicon · M1 / M2 / M3 / M4 · {macosReady ? `v${macos?.version}` : '发布验证中'}</p>
              <p className="text-sm text-slate-300 leading-relaxed">{macosReady ? '原生 InputMethodKit 输入法已完成签名、公证与发布哈希校验。' : '公开安装包只会在 Apple 证书、公证和真机兼容性验证完成后开放。'}</p>
            </div>
            <div className="mt-7 pt-6 border-t border-white/10 grid grid-cols-3 gap-3 text-xs">
              <div><span className="block text-slate-400">芯片</span><span className="font-semibold text-slate-100">{macos?.architecture ?? 'Apple Silicon'}</span></div>
              <div><span className="block text-slate-400">状态</span><span className="font-semibold text-slate-100">{macosReady ? '已验证' : '验证中'}</span></div>
              <div><span className="block text-slate-400">发布形式</span><span className="font-semibold text-slate-100">{macosReady ? '已签名公证 PKG' : '签名 PKG'}</span></div>
            </div>
            <div className="mt-7 flex items-center gap-2 rounded-2xl border border-white/10 bg-white/5 px-4 py-3 text-sm text-slate-300">
              <CircleAlert className="w-4 h-4 shrink-0 text-blue-300" />
              {macosReady ? `已验证 ${formatReleaseBytes(macos?.bytes)} · SHA-256 可在下载后独立校验。` : '当前不提供未验证下载，避免出现“无法打开”或 Gatekeeper 拦截。'}
            </div>
            <button
              type="button"
              disabled={!macosReady}
              aria-disabled={!macosReady}
              onClick={macosReady ? () => window.location.assign(macos!.downloadUrl) : undefined}
              className={`mt-4 inline-flex items-center justify-center gap-2 rounded-2xl border px-5 py-3.5 text-sm font-bold ${macosReady ? 'border-white/15 bg-white text-slate-900 hover:bg-slate-100' : 'border-white/15 bg-white/5 text-slate-400 cursor-not-allowed'}`}
            >
              {macosReady ? '下载 Mac 版' : 'Mac 安装包验证中'} <ArrowUpRight className="w-4 h-4" />
            </button>
          </article>

          <article className="bg-white rounded-3xl p-7 sm:p-8 border border-slate-200/90 shadow-xl shadow-slate-900/5 flex flex-col">
            <div className="flex items-start justify-between gap-4">
              <div className="w-12 h-12 rounded-2xl bg-slate-900 text-white grid place-items-center shadow-lg shadow-slate-900/15">
                <Smartphone className="w-6 h-6" />
              </div>
              <span className="inline-flex items-center rounded-full bg-slate-100 px-3 py-1 text-xs font-semibold text-slate-600 border border-slate-200">开发启动</span>
            </div>
            <div className="mt-7 space-y-2">
              <h3 className="text-2xl font-bold text-slate-900">GY输入法 for Android</h3>
              <p className="text-sm text-slate-500">Android 原生版 · Android 10+ · 移动端输入体验</p>
              <p className="text-sm text-slate-600 leading-relaxed">从稳定的离线拼音、简繁 EN 状态与候选交互开始，逐步接入跨设备剪贴板和按需 AI 能力。</p>
            </div>
            <div className="mt-7 pt-6 border-t border-slate-100 grid grid-cols-3 gap-3 text-xs">
              <div><span className="block text-slate-400">优先平台</span><span className="font-semibold text-slate-700">Android 10+</span></div>
              <div><span className="block text-slate-400">状态</span><span className="font-semibold text-slate-700">架构设计</span></div>
              <div><span className="block text-slate-400">发布形式</span><span className="font-semibold text-slate-700">签名 APK</span></div>
            </div>
            <div className="mt-7 flex items-center gap-2 rounded-2xl border border-slate-200 bg-slate-50 px-4 py-3 text-sm text-slate-600">
              <CircleAlert className="w-4 h-4 shrink-0 text-blue-600" />
              Android 版刚启动，不展示虚假下载按钮；内测 APK 通过真机验证后在此开放。
            </div>
            <button
              type="button"
              disabled
              aria-disabled="true"
              className="mt-4 inline-flex items-center justify-center gap-2 rounded-2xl border border-slate-200 bg-slate-100 px-5 py-3.5 text-sm font-bold text-slate-400 cursor-not-allowed"
            >
              Android 版开发中 <ArrowUpRight className="w-4 h-4" />
            </button>
          </article>
          <article className="bg-white rounded-3xl p-7 sm:p-8 border border-slate-200/90 shadow-xl shadow-slate-900/5 flex flex-col">
            <div className="flex items-start justify-between gap-4">
              <div className="w-12 h-12 rounded-2xl bg-slate-900 text-white grid place-items-center shadow-lg shadow-slate-900/15">
                <Smartphone className="w-6 h-6" />
              </div>
              <span className="inline-flex items-center rounded-full bg-slate-100 px-3 py-1 text-xs font-semibold text-slate-600 border border-slate-200">路线图</span>
            </div>
            <div className="mt-7 space-y-2">
              <h3 className="text-2xl font-bold text-slate-900">GY输入法 for iPhone</h3>
              <p className="text-sm text-slate-500">iOS / iPadOS · Keyboard Extension · 移动端输入</p>
              <p className="text-sm text-slate-600 leading-relaxed">以 iPhone 与 iPad 的原生键盘扩展为方向，先保证简繁 EN 状态、候选交互与本地词库体验，再评估跨设备能力。</p>
            </div>
            <div className="mt-7 pt-6 border-t border-slate-100 grid grid-cols-3 gap-3 text-xs">
              <div><span className="block text-slate-400">优先平台</span><span className="font-semibold text-slate-700">iOS 16+</span></div>
              <div><span className="block text-slate-400">状态</span><span className="font-semibold text-slate-700">产品规划</span></div>
              <div><span className="block text-slate-400">发布形式</span><span className="font-semibold text-slate-700">App Store</span></div>
            </div>
            <div className="mt-7 flex items-center gap-2 rounded-2xl border border-slate-200 bg-slate-50 px-4 py-3 text-sm text-slate-600">
              <CircleAlert className="w-4 h-4 shrink-0 text-blue-600" />
              iOS 版尚未启动公开测试，不提供未验证安装包。
            </div>
            <button type="button" disabled aria-disabled="true" className="mt-4 inline-flex items-center justify-center gap-2 rounded-2xl border border-slate-200 bg-slate-100 px-5 py-3.5 text-sm font-bold text-slate-400 cursor-not-allowed">
              iOS 版规划中 <ArrowUpRight className="w-4 h-4" />
            </button>
          </article>

          <article className="bg-white rounded-3xl p-7 sm:p-8 border border-slate-200/90 shadow-xl shadow-slate-900/5 flex flex-col">
            <div className="flex items-start justify-between gap-4">
              <div className="w-12 h-12 rounded-2xl bg-slate-900 text-white grid place-items-center shadow-lg shadow-slate-900/15">
                <Terminal className="w-6 h-6" />
              </div>
              <span className="inline-flex items-center rounded-full bg-slate-100 px-3 py-1 text-xs font-semibold text-slate-600 border border-slate-200">路线图</span>
            </div>
            <div className="mt-7 space-y-2">
              <h3 className="text-2xl font-bold text-slate-900">GY输入法 for Linux</h3>
              <p className="text-sm text-slate-500">Linux · IBus / Fcitx5 · x86_64 / ARM64</p>
              <p className="text-sm text-slate-600 leading-relaxed">面向桌面 Linux 的输入框架适配将从 IBus 与 Fcitx5 开始，优先做稳定输入、候选窗与本地词库，再扩展更多发行版。</p>
            </div>
            <div className="mt-7 pt-6 border-t border-slate-100 grid grid-cols-3 gap-3 text-xs">
              <div><span className="block text-slate-400">优先框架</span><span className="font-semibold text-slate-700">IBus / Fcitx5</span></div>
              <div><span className="block text-slate-400">状态</span><span className="font-semibold text-slate-700">技术调研</span></div>
              <div><span className="block text-slate-400">发布形式</span><span className="font-semibold text-slate-700">包仓 / Flatpak</span></div>
            </div>
            <div className="mt-7 flex items-center gap-2 rounded-2xl border border-slate-200 bg-slate-50 px-4 py-3 text-sm text-slate-600">
              <CircleAlert className="w-4 h-4 shrink-0 text-blue-600" />
              Linux 版会先完成主流桌面环境验证，再开放安装包。
            </div>
            <button type="button" disabled aria-disabled="true" className="mt-4 inline-flex items-center justify-center gap-2 rounded-2xl border border-slate-200 bg-slate-100 px-5 py-3.5 text-sm font-bold text-slate-400 cursor-not-allowed">
              Linux 版调研中 <ArrowUpRight className="w-4 h-4" />
            </button>
          </article>
        </div>

        <div className="mt-5 rounded-2xl border border-slate-200 bg-white px-5 py-4 flex flex-col sm:flex-row sm:items-center gap-4 text-sm">
          <div className="flex items-center gap-2 text-slate-600 min-w-0">
            <ShieldCheck className="w-5 h-5 text-blue-600 shrink-0" />
            <span className="font-medium shrink-0">Windows SHA-256</span>
            <code className="font-mono text-xs text-slate-500 truncate">{windows?.sha256 ?? '发布验证中'}</code>
          </div>
          <button disabled={!windowsReady} onClick={handleCopyHash} className="sm:ml-auto inline-flex items-center justify-center gap-1.5 text-xs font-semibold text-blue-700 hover:text-blue-800 shrink-0 disabled:text-slate-400 disabled:cursor-not-allowed">
            {copiedHash ? <><Check className="w-4 h-4" /> 已复制</> : <><Copy className="w-4 h-4" /> 复制校验码</>}
          </button>
        </div>
      </div>
    </section>
  );
};




