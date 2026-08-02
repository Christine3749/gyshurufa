import React from 'react';
import { X, ShieldCheck, Lock, HardDrive, Cpu, EyeOff, FileText, CheckCircle2 } from 'lucide-react';

interface PrivacyModalProps {
  isOpen: boolean;
  onClose: () => void;
}

export const PrivacyModal: React.FC<PrivacyModalProps> = ({ isOpen, onClose }) => {
  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-900/60 backdrop-blur-sm animate-fadeIn">
      <div 
        className="relative w-full max-w-3xl max-h-[85vh] bg-white rounded-2xl shadow-2xl border border-slate-100 overflow-hidden flex flex-col text-slate-800"
        onClick={(e) => e.stopPropagation()}
      >
        {/* Header */}
        <div className="flex items-center justify-between px-6 py-5 border-b border-slate-100 bg-slate-50/80 shrink-0">
          <div className="flex items-center space-x-3">
            <div className="w-10 h-10 rounded-xl bg-blue-50 border border-blue-200 flex items-center justify-center text-blue-600">
              <ShieldCheck className="w-5 h-5" />
            </div>
            <div>
              <h3 className="text-lg font-bold text-slate-900">GY输入法 隐私与数据安全宣言</h3>
              <p className="text-xs text-slate-500">官方透明白皮书 · 默认本地优先原则</p>
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

        {/* Scrollable Content */}
        <div className="p-6 overflow-y-auto space-y-6 text-sm leading-relaxed text-slate-600">
          <div className="p-4 rounded-xl bg-blue-50/60 border border-blue-100 text-blue-900 text-xs sm:text-sm">
            <p className="font-semibold mb-1">TL;DR 核心承诺：</p>
            GY输入法承诺，您的基础按键序列、个人词库、剪贴板历史**默认 100% 存在于 Windows 本地**。未经用户主动触发，绝不向上线任何服务器上传打字内容。
          </div>

          {/* Section 1 */}
          <div className="space-y-3">
            <h4 className="text-base font-bold text-slate-900 flex items-center gap-2">
              <HardDrive className="w-4 h-4 text-blue-600" />
              1. 基础输入与词库完全本地处理
            </h4>
            <p>
              在默认状态下，GY输入法采用完全离线的 C++ 核心引擎进行拼音切分、词频统计与词库联想。
            </p>
            <ul className="space-y-2 text-xs sm:text-sm pl-4 list-disc text-slate-600">
              <li>**按键序列（Keylogger Free）**：只在系统 TSF 输入法框架本地缓冲区运行，不存留未上屏日志。</li>
              <li>**自适应词库**：根据您的打字习惯在本地加密生成 SQLite/JSON 格式文件，路径完全由您掌控。</li>
              <li>**剪贴板历史**：可选功能，仅保存在本机的 RAM 内存或加密硬盘，关闭软件即物理清空。</li>
            </ul>
          </div>

          {/* Section 2 */}
          <div className="space-y-3">
            <h4 className="text-base font-bold text-slate-900 flex items-center gap-2">
              <Cpu className="w-4 h-4 text-blue-600" />
              2. AI 增值功能的可控触发机制
            </h4>
            <p>
              GY输入法提供包含“改写润色、翻译、摘要、快捷短语”在内的 AI 原生能力。
            </p>
            <div className="p-3 rounded-lg bg-slate-50 border border-slate-200 text-xs space-y-1.5">
              <div className="flex items-center gap-2 text-slate-800 font-semibold">
                <CheckCircle2 className="w-4 h-4 text-emerald-600" /> 用户主动触发原则 (Opt-in)
              </div>
              <p className="text-slate-600">
                AI 功能绝不后台静默嗅探。仅当您主动按快捷键（如 Alt+/, Alt+T）或在候选框中点击 AI 按钮时，选定的单句文本才会通过 TLS 1.3 传输加密请求至 GSYEN AI 节点。
              </p>
            </div>
            <p className="text-xs text-slate-500">
              传输数据仅作临时处理，完成推理后即刻丢弃，不用于任何大语言模型（LLM）的训练数据收集。
            </p>
          </div>

          {/* Section 3 */}
          <div className="space-y-3">
            <h4 className="text-base font-bold text-slate-900 flex items-center gap-2">
              <EyeOff className="w-4 h-4 text-blue-600" />
              3. 零广告追踪与透明审计
            </h4>
            <ul className="space-y-2 text-xs sm:text-sm pl-4 list-disc text-slate-600">
              <li>**无广告 SDK**：绝不集成任何第三方广告跟踪、推送、行为画像等侵犯隐私的 SDK。</li>
              <li>**防火墙兼容**：您可以使用 Windows Defender 防火墙将 GY输入法设为禁止联网，基础输入功能不受影响。</li>
              <li>**网络审计台**：软件内置网络诊断工具，可实时监控并记录所有的连接域名（仅为控制台 AI 代理），完全公开透明。</li>
            </ul>
          </div>

          {/* Section 4 */}
          <div className="space-y-3 border-t border-slate-100 pt-4">
            <h4 className="text-base font-bold text-slate-900 flex items-center gap-2">
              <Lock className="w-4 h-4 text-blue-600" />
              4. 数据的控制权归您所有
            </h4>
            <p className="text-xs sm:text-sm">
              您可以随时在软件设置中点击“一键清除本地词库”或导出为标准纯文本。卸载软件时，勾选“彻底删除数据”将不留下任何残余痕迹。
            </p>
          </div>
        </div>

        {/* Footer */}
        <div className="px-6 py-4 bg-slate-50 border-t border-slate-100 flex items-center justify-between shrink-0">
          <span className="text-xs text-slate-500">母品牌 GSYEN 智能安全规范</span>
          <button
            onClick={onClose}
            className="px-5 py-2 rounded-xl bg-slate-900 hover:bg-slate-800 text-white font-medium text-xs sm:text-sm transition-all"
          >
            我已了解
          </button>
        </div>
      </div>
    </div>
  );
};
