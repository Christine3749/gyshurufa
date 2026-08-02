import React, { useState } from 'react';
import { Layers, ArrowRight, CheckCircle2, Cpu, Laptop, Terminal, FileText, LayoutGrid } from 'lucide-react';
import { ECOSYSTEM_MODULES } from '../data/content';

interface EcosystemSectionProps {
  onOpenAboutGSYEN: () => void;
}

export const EcosystemSection: React.FC<EcosystemSectionProps> = ({ onOpenAboutGSYEN }) => {
  const [activeModuleId, setActiveModuleId] = useState(ECOSYSTEM_MODULES[0].id);

  return (
    <section id="ecosystem" className="py-24 bg-slate-900 text-white relative overflow-hidden">
      {/* Background Subtle Gradient Glow */}
      <div className="absolute top-0 right-1/4 w-96 h-96 bg-blue-600/10 rounded-full filter blur-3xl pointer-events-none" />
      <div className="absolute bottom-0 left-1/4 w-96 h-96 bg-indigo-600/10 rounded-full filter blur-3xl pointer-events-none" />

      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 relative z-10">
        
        {/* Header */}
        <div className="text-center max-w-3xl mx-auto space-y-4 mb-16">
          <div className="inline-flex items-center gap-2 px-3.5 py-1.5 rounded-full bg-slate-800 text-blue-400 text-xs font-semibold border border-slate-700">
            <Layers className="w-3.5 h-3.5" />
            GSYEN 智能工作生态系统
          </div>
          <h2 className="text-3xl sm:text-4xl font-extrabold tracking-tight">
            不只是输入法。
          </h2>
          <p className="text-slate-400 text-base leading-relaxed">
            GY输入法是 GSYEN AI 原生软件生态的高频交互入口。每一次敲击，都能无缝呼出生态内的各类工具与智能化工作流。
          </p>
        </div>

        {/* Modules Grid */}
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6 mb-12">
          {ECOSYSTEM_MODULES.map((mod) => {
            const isActive = activeModuleId === mod.id;
            return (
              <div
                key={mod.id}
                onClick={() => setActiveModuleId(mod.id)}
                className={`p-6 rounded-2xl transition-all cursor-pointer border relative flex flex-col justify-between ${
                  isActive
                    ? 'bg-slate-800/90 border-blue-500 shadow-xl ring-2 ring-blue-500/20'
                    : 'bg-slate-800/40 hover:bg-slate-800/70 border-slate-700/60'
                }`}
              >
                <div className="space-y-4">
                  <div className="flex items-center justify-between">
                    <span className="text-[10px] font-mono px-2 py-0.5 rounded bg-blue-950 text-blue-300 border border-blue-800">
                      {mod.category}
                    </span>
                    <span className="text-xs text-emerald-400 flex items-center gap-1 font-medium">
                      <CheckCircle2 className="w-3.5 h-3.5" />
                      {mod.status}
                    </span>
                  </div>

                  <div className="space-y-2">
                    <h3 className="text-lg font-bold text-white">{mod.name}</h3>
                    <p className="text-xs text-slate-400 leading-relaxed">{mod.description}</p>
                  </div>
                </div>

                <div className="pt-4 mt-6 border-t border-slate-700/60 flex items-center justify-between text-xs text-slate-400">
                  <span>高频唤醒指令</span>
                  <span className={`font-semibold flex items-center gap-1 ${isActive ? 'text-blue-400' : 'text-slate-500'}`}>
                    查看协同 <ArrowRight className="w-3.5 h-3.5" />
                  </span>
                </div>
              </div>
            );
          })}
        </div>

        {/* Seamless Interactive Workflow Preview Box */}
        <div className="p-6 sm:p-8 rounded-3xl bg-slate-800/80 border border-slate-700/80 space-y-6">
          <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 border-b border-slate-700/80 pb-4">
            <div>
              <h3 className="text-base font-bold text-white flex items-center gap-2">
                <Laptop className="w-4 h-4 text-blue-400" />
                输入法 ➔ GSYEN 软件生态的超集联动
              </h3>
              <p className="text-xs text-slate-400 mt-0.5">
                无需频繁切换软件窗口，输入法即是统一的操控控制台
              </p>
            </div>

            <button
              onClick={onOpenAboutGSYEN}
              className="text-xs text-blue-400 hover:text-blue-300 font-medium flex items-center gap-1 self-start sm:self-auto"
            >
              深入了解 GSYEN 品牌理念 <ArrowRight className="w-3.5 h-3.5" />
            </button>
          </div>

          <div className="p-4 rounded-xl bg-slate-900 border border-slate-700 font-mono text-xs space-y-2 text-slate-300">
            <div className="text-slate-500">// 在输入法候选框中输入指令协同 GSYEN 生态</div>
            <div className="text-blue-400 font-bold">&gt; 打字触发: /workspace new "整理下周产品路线图"</div>
            <div className="p-3 rounded-lg bg-slate-950 border border-slate-800 text-slate-200 text-xs">
              系统响应：已联动 [GSYEN Workspace] 创建全套工作任务，自动补全日期变量【2026-08-01】，并自动关联至 GY输入法个人近7日高频词库。
            </div>
          </div>
        </div>

      </div>
    </section>
  );
};
