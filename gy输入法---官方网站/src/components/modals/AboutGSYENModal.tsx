import React from 'react';
import { X, Layers, Sparkles, Shield, Cpu, ExternalLink, Globe } from 'lucide-react';
import { BRAND_INFO, ECOSYSTEM_MODULES } from '../../data/content';

interface AboutGSYENModalProps {
  isOpen: boolean;
  onClose: () => void;
}

export const AboutGSYENModal: React.FC<AboutGSYENModalProps> = ({ isOpen, onClose }) => {
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
            <div className="w-10 h-10 rounded-xl bg-slate-900 text-white flex items-center justify-center font-bold text-lg shadow-md">
              GS
            </div>
            <div>
              <h3 className="text-lg font-bold text-slate-900">关于 GSYEN 智能工作生态</h3>
              <p className="text-xs text-slate-500">GY输入法母品牌 · AI 原生生产力套件</p>
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

        {/* Content */}
        <div className="p-6 overflow-y-auto space-y-6 text-sm text-slate-600">
          <div className="space-y-3">
            <h4 className="text-base font-bold text-slate-900">GSYEN 品牌理念</h4>
            <p className="leading-relaxed">
              GSYEN 致力于重新思考人类与计算机交互的界面形态。我们相信，AI 不应该是繁复臃肿的浮夸聊天框，而应当静默融入日常打字、记录、管理与协作的第一线。
            </p>
            <p className="leading-relaxed">
              <span className="font-semibold text-slate-800">GY输入法</span> 作为 GSYEN 生态中最核心的高频交互入口，承担着“极速输入 + 离线安全 + 上下文智能触发”的基础使命。
            </p>
          </div>

          {/* Pillars */}
          <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
            <div className="p-3.5 rounded-xl bg-slate-50 border border-slate-100 space-y-1">
              <div className="flex items-center gap-1.5 text-xs font-bold text-slate-900">
                <Cpu className="w-4 h-4 text-blue-600" />
                高性能极轻量
              </div>
              <p className="text-xs text-slate-500">底层的 C++ 架构保障极致流畅与极低资源开销。</p>
            </div>

            <div className="p-3.5 rounded-xl bg-slate-50 border border-slate-100 space-y-1">
              <div className="flex items-center gap-1.5 text-xs font-bold text-slate-900">
                <Shield className="w-4 h-4 text-blue-600" />
                本地数据自主
              </div>
              <p className="text-xs text-slate-500">捍卫用户隐私，个人资产与文字记录本地封存。</p>
            </div>

            <div className="p-3.5 rounded-xl bg-slate-50 border border-slate-100 space-y-1">
              <div className="flex items-center gap-1.5 text-xs font-bold text-slate-900">
                <Sparkles className="w-4 h-4 text-blue-600" />
                无缝生态联动
              </div>
              <p className="text-xs text-slate-500">一个输入法，连接工作区、笔记、终端与脑图。</p>
            </div>
          </div>

          {/* Ecosystem Grid */}
          <div className="space-y-3">
            <h4 className="text-xs font-bold uppercase tracking-wider text-slate-400 flex items-center gap-1">
              <Layers className="w-3.5 h-3.5" /> GSYEN 家族工具概览
            </h4>
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
              {ECOSYSTEM_MODULES.map((item) => (
                <div key={item.id} className="p-3 rounded-lg border border-slate-100 bg-slate-50/50 hover:bg-slate-50 transition-colors">
                  <div className="flex items-center justify-between mb-1">
                    <span className="font-semibold text-xs text-slate-900">{item.name}</span>
                    <span className="text-[10px] px-1.5 py-0.5 rounded bg-blue-50 text-blue-700 font-medium">{item.status}</span>
                  </div>
                  <p className="text-xs text-slate-500">{item.description}</p>
                </div>
              ))}
            </div>
          </div>

          <div className="p-3 rounded-xl bg-slate-900 text-slate-300 text-xs flex items-center justify-between">
            <div className="flex items-center gap-2">
              <Globe className="w-4 h-4 text-blue-400" />
              <span>GY输入法专属域名：<strong className="text-white">{BRAND_INFO.domain}</strong></span>
            </div>
            <span className="text-slate-400">Copyright © 2026 GSYEN</span>
          </div>
        </div>

        {/* Footer */}
        <div className="px-6 py-4 bg-slate-50 border-t border-slate-100 flex items-center justify-between shrink-0">
          <span className="text-xs text-slate-500">GSYEN Intelligent Workspace</span>
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
