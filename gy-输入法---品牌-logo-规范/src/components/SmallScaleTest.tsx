import React from 'react';
import { GYSystemAppIcon, GYSymbolPathSVG } from './GYWordmarkLogo';

export const SmallScaleTest: React.FC = () => {
  const scales = [
    { size: 16 as const, label: '16px', desc: 'Windows 任务栏 / 系统托盘' },
    { size: 24 as const, label: '24px', desc: 'IME 语言栏 / 状态区' },
    { size: 32 as const, label: '32px', desc: '桌面快捷方式 / 任务管理器' },
    { size: 48 as const, label: '48px', desc: 'Windows 开始菜单 / 应用列表' },
  ];

  return (
    <div className="w-full max-w-4xl mx-auto my-8 bg-white dark:bg-neutral-900 rounded-2xl p-6 border border-neutral-200 dark:border-neutral-800 shadow-xs">
      <div className="pb-4 mb-6 border-b border-neutral-200 dark:border-neutral-800">
        <div className="flex items-center gap-2">
          <h3 className="text-sm font-semibold tracking-wider text-neutral-900 dark:text-neutral-100 uppercase font-mono">
            小尺寸系统图标规范测试 (16px / 24px / 32px)
          </h3>
          <span className="bg-neutral-100 dark:bg-neutral-800 text-neutral-700 dark:text-neutral-300 text-[10px] font-mono px-2 py-0.5 rounded uppercase font-semibold">
            白色 GY + 深墨黑背景 (#111318)
          </span>
        </div>
        <p className="text-xs text-neutral-500 dark:text-neutral-400 mt-1">
          规范要求：不含“输入法”副标题，大写字母 GY 在小尺寸系统像素下高度清晰可读
        </p>
      </div>

      {/* Grid of Sizes */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        {scales.map((item) => (
          <div
            key={item.size}
            className="flex flex-col items-center justify-center p-5 rounded-xl border border-neutral-200/80 dark:border-neutral-800 bg-neutral-50/70 dark:bg-neutral-950/60 hover:border-neutral-300 dark:hover:border-neutral-700 transition-all"
          >
            {/* Real 1:1 Rendering Icon */}
            <div className="mb-4 flex items-center justify-center h-16 w-20 bg-white dark:bg-neutral-900 rounded-lg border border-neutral-200/60 dark:border-neutral-800 shadow-xs relative">
              <GYSystemAppIcon size={item.size} />
              <span className="absolute bottom-1 right-1 text-[9px] font-mono font-medium text-neutral-400 dark:text-neutral-500">
                1:1
              </span>
            </div>

            {/* Size Label */}
            <div className="text-center">
              <span className="font-mono font-bold text-sm text-neutral-900 dark:text-neutral-100">
                {item.label}
              </span>
              <p className="text-[11px] text-neutral-500 dark:text-neutral-400 mt-0.5">
                {item.desc}
              </p>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
};
