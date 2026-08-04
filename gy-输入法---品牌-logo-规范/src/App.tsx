import React, { useState } from 'react';
import { GYWordmarkLogo } from './components/GYWordmarkLogo';
import { SmallScaleTest } from './components/SmallScaleTest';
import { SystemPreview } from './components/SystemPreview';
import { BrandDetails } from './components/BrandDetails';
import { Sun, Moon } from 'lucide-react';

export default function App() {
  const [darkMode, setDarkMode] = useState<boolean>(false);

  // 严格要求：深色模式使用纯白色 #FFFFFF；浅色模式使用深墨黑 #111318
  const wordmarkColor = darkMode ? '#FFFFFF' : '#111318';

  return (
    <div className={`min-h-screen transition-colors duration-300 font-sans ${darkMode ? 'dark bg-[#0A0C10] text-white' : 'bg-[#FAFAFB] text-[#111318]'}`}>
      
      {/* 顶栏控制 - 极其简洁纯粹 */}
      <header className="sticky top-0 z-30 backdrop-blur-md bg-white/80 dark:bg-[#0A0C10]/80 border-b border-neutral-200/60 dark:border-neutral-800/80 px-4 py-3">
        <div className="max-w-5xl mx-auto flex items-center justify-between">
          <div className="flex items-center gap-2">
            <span className="font-mono text-xs font-bold tracking-widest uppercase text-neutral-400 dark:text-neutral-500">
              GY 输入法 官方标准字标规范
            </span>
          </div>

          {/* 深/浅色模式切换 */}
          <button
            onClick={() => setDarkMode(!darkMode)}
            className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-neutral-100 dark:bg-neutral-800 text-neutral-700 dark:text-neutral-300 hover:bg-neutral-200 dark:hover:bg-neutral-700 transition-colors cursor-pointer text-xs font-medium"
            title="切换深色/浅色模式"
          >
            {darkMode ? <Sun className="w-3.5 h-3.5 text-amber-400" /> : <Moon className="w-3.5 h-3.5 text-neutral-600" />}
            <span>{darkMode ? '深色模式 (纯白 GY)' : '浅色模式 (深墨黑 GY)'}</span>
          </button>
        </div>
      </header>

      <main className="max-w-5xl mx-auto px-4 py-10 space-y-16">
        
        {/* 1. 官网主文字标 (Compact GY Master Wordmark + 副标题“输入法”) */}
        <section className="flex flex-col items-center justify-center py-12 text-center">
          <div className="p-8 my-2 transition-transform hover:scale-[1.01]">
            <GYWordmarkLogo
              size={120}
              color={wordmarkColor}
              showSubtitle={true}
            />
          </div>

          <p className="mt-4 text-xs text-neutral-500 dark:text-neutral-400 max-w-sm mx-auto font-sans leading-relaxed">
            标准粗体无衬线 “GY” 大写字母。字距紧凑对齐，清晰、专业、安静。
          </p>
        </section>

        <hr className="border-neutral-200/80 dark:border-neutral-800/80 max-w-4xl mx-auto" />

        {/* 2. 黑底与白底反色版本 (Black & White Inverted Contrast Specs) */}
        <section className="space-y-6">
          <div className="text-center">
            <h2 className="text-xs font-mono font-semibold tracking-widest uppercase text-neutral-400 dark:text-neutral-500">
              反色版本对比 / Inverted Contrast
            </h2>
            <p className="text-sm font-semibold text-neutral-800 dark:text-neutral-200 mt-1">
              浅色画布 (深墨黑 #111318) 与 深色画布 (纯白 #FFFFFF)
            </p>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 gap-6 max-w-4xl mx-auto">
            {/* 白底黑标 (Light Canvas - Ink Black) */}
            <div className="bg-white rounded-2xl p-10 border border-neutral-200/90 shadow-xs flex flex-col items-center justify-center text-center space-y-6 min-h-[240px]">
              <span className="text-[10px] font-mono uppercase font-semibold text-neutral-400 bg-neutral-100 px-2.5 py-1 rounded-full">
                浅色模式 / 纯白画布
              </span>
              <GYWordmarkLogo size={80} color="#111318" showSubtitle={true} />
            </div>

            {/* 黑底白标 (Dark Canvas - Pure White) */}
            <div className="bg-[#111318] rounded-2xl p-10 border border-neutral-800 shadow-xs flex flex-col items-center justify-center text-center space-y-6 min-h-[240px]">
              <span className="text-[10px] font-mono uppercase font-semibold text-neutral-500 bg-neutral-900 px-2.5 py-1 rounded-full">
                深色模式 / 深墨夜色 (#111318)
              </span>
              <GYWordmarkLogo size={80} color="#FFFFFF" showSubtitle={true} />
            </div>
          </div>
        </section>

        {/* 3. 16px, 24px, 32px 系统图标规范 */}
        <section>
          <SmallScaleTest />
        </section>

        {/* 4. 系统级原生集成预览 */}
        <section>
          <SystemPreview />
        </section>

        {/* 5. 矢量 SVG 资源与 ICO 图标导出 */}
        <section>
          <BrandDetails color={wordmarkColor} />
        </section>

      </main>

      {/* Footer Minimal Copyright */}
      <footer className="border-t border-neutral-200/60 dark:border-neutral-800/80 py-8 px-4 text-center text-xs font-mono text-neutral-400">
        <p>GY 输入法 品牌标识规范 &copy; 2026. 系统级顺滑中文输入工具.</p>
      </footer>
    </div>
  );
}
