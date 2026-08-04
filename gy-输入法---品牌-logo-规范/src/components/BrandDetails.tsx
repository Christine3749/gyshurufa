import React, { useState } from 'react';
import { Copy, Download, Check, Code, Shield } from 'lucide-react';

export const BrandDetails: React.FC<{ color?: string }> = ({ color = '#111318' }) => {
  const [copiedWordmark, setCopiedWordmark] = useState(false);
  const [copiedIcon, setCopiedIcon] = useState(false);

  // 主 GY 文字标 (SVG)
  const rawWordmarkSVG = `<svg width="156" height="100" viewBox="0 0 156 100" fill="none" xmlns="http://www.w3.org/2000/svg">
  <!-- GY 输入法 标准字标 (Compact GY Wordmark) -->
  <path d="M 72 26 C 65 18, 54 13, 40 13 C 21 13, 8 28, 8 50 C 8 72, 21 87, 40 87 C 56 87, 68 77, 72 63 L 72 52 L 40 52 L 40 66 L 57 66 C 54 72, 48 74, 40 74 C 28 74, 21 64, 21 50 C 21 36, 28 26, 40 26 C 49 26, 56 31, 60 37 L 72 26 Z" fill="${color}" />
  <path d="M 80 15 L 94 15 L 114 50 L 134 15 L 148 15 L 121 60 L 121 87 L 107 87 L 107 60 L 80 15 Z" fill="${color}" />
</svg>`;

  // 16px/24px/32px 系统图标 (深墨黑背景 + 白色 GY)
  const rawAppIconSVG = `<svg width="32" height="32" viewBox="0 0 32 32" fill="none" xmlns="http://www.w3.org/2000/svg">
  <rect width="32" height="32" rx="7" fill="#111318"/>
  <g transform="translate(3.5, 7.5) scale(0.16)">
    <path d="M 72 26 C 65 18, 54 13, 40 13 C 21 13, 8 28, 8 50 C 8 72, 21 87, 40 87 C 56 87, 68 77, 72 63 L 72 52 L 40 52 L 40 66 L 57 66 C 54 72, 48 74, 40 74 C 28 74, 21 64, 21 50 C 21 36, 28 26, 40 26 C 49 26, 56 31, 60 37 L 72 26 Z" fill="#FFFFFF"/>
    <path d="M 80 15 L 94 15 L 114 50 L 134 15 L 148 15 L 121 60 L 121 87 L 107 87 L 107 60 L 80 15 Z" fill="#FFFFFF"/>
  </g>
</svg>`;

  const handleCopy = (code: string, isIcon: boolean) => {
    navigator.clipboard.writeText(code);
    if (isIcon) {
      setCopiedIcon(true);
      setTimeout(() => setCopiedIcon(false), 2000);
    } else {
      setCopiedWordmark(true);
      setTimeout(() => setCopiedWordmark(false), 2000);
    }
  };

  const handleDownload = (code: string, filename: string) => {
    const blob = new Blob([code], { type: 'image/svg+xml' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = filename;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
  };

  return (
    <div className="w-full max-w-4xl mx-auto my-8 grid grid-cols-1 md:grid-cols-2 gap-6">
      {/* 1. 主文字标 GY (Wordmark) 导出 */}
      <div className="bg-white dark:bg-neutral-900 rounded-2xl p-6 border border-neutral-200 dark:border-neutral-800 shadow-xs flex flex-col justify-between">
        <div>
          <div className="flex items-center justify-between mb-4">
            <div className="flex items-center gap-2">
              <Code className="w-4 h-4 text-neutral-800 dark:text-neutral-200" />
              <h3 className="text-sm font-semibold text-neutral-900 dark:text-neutral-100 uppercase font-mono">
                标准 GY 文字标 SVG
              </h3>
            </div>
            <span className="text-[10px] font-mono text-neutral-400">Wordmark Vector</span>
          </div>

          <div className="bg-neutral-900 text-neutral-200 rounded-xl p-3 font-mono text-[11px] overflow-x-auto border border-neutral-800 max-h-36 scrollbar-thin">
            <pre className="text-neutral-300 leading-snug">{rawWordmarkSVG}</pre>
          </div>
        </div>

        <div className="flex items-center gap-3 mt-6">
          <button
            onClick={() => handleCopy(rawWordmarkSVG, false)}
            className="flex-1 flex items-center justify-center gap-2 px-4 py-2.5 rounded-xl bg-neutral-900 dark:bg-white text-white dark:text-neutral-900 font-medium text-xs hover:opacity-90 transition-opacity cursor-pointer shadow-xs"
          >
            {copiedWordmark ? <Check className="w-3.5 h-3.5 text-emerald-400" /> : <Copy className="w-3.5 h-3.5" />}
            <span>{copiedWordmark ? '已复制文字标 SVG' : '复制文字标 SVG'}</span>
          </button>

          <button
            onClick={() => handleDownload(rawWordmarkSVG, 'GY-Wordmark.svg')}
            className="flex items-center justify-center gap-2 px-4 py-2.5 rounded-xl bg-neutral-100 dark:bg-neutral-800 text-neutral-800 dark:text-neutral-200 font-medium text-xs hover:bg-neutral-200 dark:hover:bg-neutral-700 transition-colors cursor-pointer border border-neutral-200 dark:border-neutral-700"
          >
            <Download className="w-3.5 h-3.5" />
            <span>下载 .svg</span>
          </button>
        </div>
      </div>

      {/* 2. 系统图标 (Windows App ICO / Tray Icon) 导出 */}
      <div className="bg-white dark:bg-neutral-900 rounded-2xl p-6 border border-neutral-200 dark:border-neutral-800 shadow-xs flex flex-col justify-between">
        <div>
          <div className="flex items-center justify-between mb-4">
            <div className="flex items-center gap-2">
              <Shield className="w-4 h-4 text-neutral-800 dark:text-neutral-200" />
              <h3 className="text-sm font-semibold text-neutral-900 dark:text-neutral-100 uppercase font-mono">
                系统图标 .ICO / App Icon SVG
              </h3>
            </div>
            <span className="text-[10px] font-mono text-neutral-400">#111318 + White GY</span>
          </div>

          <div className="bg-neutral-900 text-neutral-200 rounded-xl p-3 font-mono text-[11px] overflow-x-auto border border-neutral-800 max-h-36 scrollbar-thin">
            <pre className="text-neutral-300 leading-snug">{rawAppIconSVG}</pre>
          </div>
        </div>

        <div className="flex items-center gap-3 mt-6">
          <button
            onClick={() => handleCopy(rawAppIconSVG, true)}
            className="flex-1 flex items-center justify-center gap-2 px-4 py-2.5 rounded-xl bg-neutral-900 dark:bg-white text-white dark:text-neutral-900 font-medium text-xs hover:opacity-90 transition-opacity cursor-pointer shadow-xs"
          >
            {copiedIcon ? <Check className="w-3.5 h-3.5 text-emerald-400" /> : <Copy className="w-3.5 h-3.5" />}
            <span>{copiedIcon ? '已复制图标 SVG' : '复制系统图标 SVG'}</span>
          </button>

          <button
            onClick={() => handleDownload(rawAppIconSVG, 'GY-AppIcon.svg')}
            className="flex items-center justify-center gap-2 px-4 py-2.5 rounded-xl bg-neutral-100 dark:bg-neutral-800 text-neutral-800 dark:text-neutral-200 font-medium text-xs hover:bg-neutral-200 dark:hover:bg-neutral-700 transition-colors cursor-pointer border border-neutral-200 dark:border-neutral-700"
          >
            <Download className="w-3.5 h-3.5" />
            <span>下载 .svg</span>
          </button>
        </div>
      </div>
    </div>
  );
};
