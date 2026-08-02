import React, { useState } from 'react';
import { Zap, Target, ShieldCheck, Check, Cpu, Gauge, Clock, ArrowUpRight } from 'lucide-react';
import { CORE_VALUES } from '../data/content';

export const CoreValues: React.FC = () => {
  const [activeValueTab, setActiveValueTab] = useState(0);
  const selectedValue = CORE_VALUES[activeValueTab];

  return (
    <section id="values" className="py-24 bg-white relative overflow-hidden">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        
        {/* Section Header */}
        <div className="text-center max-w-3xl mx-auto space-y-4 mb-16">
          <div className="inline-flex items-center gap-2 px-3 py-1 rounded-full bg-slate-100 text-slate-700 text-xs font-semibold">
            <Gauge className="w-3.5 h-3.5 text-blue-600" />
            三大核心柱石
          </div>
          <h2 className="text-3xl sm:text-4xl font-extrabold text-slate-900 tracking-tight">
            快、准、安心。<br />
            <span className="text-blue-600">回归输入法的纯粹本质。</span>
          </h2>
          <p className="text-slate-600 text-base leading-relaxed">
            摒弃繁复冗余的弹窗广告与捆绑软件，GY输入法专注于打字本身的流畅感与绝对安全。
          </p>
        </div>

        {/* Value Selector Tabs */}
        <div className="flex justify-center mb-12">
          <div className="inline-flex p-1.5 bg-slate-100 rounded-2xl border border-slate-200/80 gap-1 sm:gap-2">
            {CORE_VALUES.map((val, idx) => {
              const isActive = activeValueTab === idx;
              return (
                <button
                  key={val.id}
                  onClick={() => setActiveValueTab(idx)}
                  className={`px-5 py-2.5 rounded-xl text-sm font-semibold transition-all flex items-center gap-2 ${
                    isActive
                      ? 'bg-white text-blue-600 shadow-sm border border-slate-200/60'
                      : 'text-slate-600 hover:text-slate-900'
                  }`}
                >
                  {val.id === 'fast' && <Zap className="w-4 h-4 text-amber-500" />}
                  {val.id === 'accurate' && <Target className="w-4 h-4 text-emerald-500" />}
                  {val.id === 'secure' && <ShieldCheck className="w-4 h-4 text-blue-600" />}
                  <span>{val.id === 'fast' ? '快：极致轻量' : val.id === 'accurate' ? '准：上下文精准' : '安心：本地优先'}</span>
                </button>
              );
            })}
          </div>
        </div>

        {/* Main Active Value Showcase Card */}
        <div className="bg-slate-50/70 border border-slate-200/80 rounded-3xl p-6 sm:p-10 shadow-sm space-y-8 animate-fadeIn">
          
          <div className="grid grid-cols-1 lg:grid-cols-12 gap-8 items-center">
            
            {/* Left Description Column */}
            <div className="lg:col-span-6 space-y-6">
              <div className="space-y-2">
                <span className="text-xs font-mono font-bold px-3 py-1 rounded-full bg-blue-50 text-blue-700 border border-blue-200/60 inline-block">
                  {selectedValue.highlight}
                </span>
                <h3 className="text-2xl sm:text-3xl font-extrabold text-slate-900">
                  {selectedValue.title}
                </h3>
                <p className="text-slate-600 text-sm sm:text-base leading-relaxed pt-1">
                  {selectedValue.subtitle}
                </p>
              </div>

              {/* Feature Bullet Points */}
              <div className="space-y-3 pt-2">
                {selectedValue.features.map((feat, i) => (
                  <div key={i} className="flex items-start gap-3">
                    <div className="w-5 h-5 rounded-full bg-blue-100 text-blue-600 flex items-center justify-center shrink-0 mt-0.5">
                      <Check className="w-3 h-3" />
                    </div>
                    <span className="text-sm font-medium text-slate-800">{feat}</span>
                  </div>
                ))}
              </div>
            </div>

            {/* Right Benchmark Metrics Column */}
            <div className="lg:col-span-6">
              <div className="bg-white p-6 sm:p-8 rounded-2xl border border-slate-200/80 shadow-md space-y-6">
                <h4 className="text-xs font-bold uppercase tracking-wider text-slate-400 flex items-center justify-between">
                  <span>实测性能指标对标</span>
                  <span className="text-blue-600 font-mono text-[11px]">Windows 11 23H2 测试环境</span>
                </h4>

                <div className="space-y-5">
                  {selectedValue.metrics.map((m, idx) => (
                    <div key={idx} className="space-y-1.5 border-b border-slate-100 pb-4 last:border-none last:pb-0">
                      <div className="flex items-center justify-between">
                        <span className="text-xs text-slate-500 font-medium">{m.label}</span>
                        <span className="text-lg font-bold text-slate-900 font-mono">{m.value}</span>
                      </div>
                      <div className="w-full bg-slate-100 h-2 rounded-full overflow-hidden">
                        <div 
                          className="bg-blue-600 h-full rounded-full transition-all duration-700"
                          style={{ width: idx === 0 ? '90%' : idx === 1 ? '75%' : '100%' }}
                        />
                      </div>
                      <p className="text-[11px] text-slate-400 text-right">
                        对比: {m.comp}
                      </p>
                    </div>
                  ))}
                </div>
              </div>
            </div>

          </div>

        </div>

      </div>
    </section>
  );
};
