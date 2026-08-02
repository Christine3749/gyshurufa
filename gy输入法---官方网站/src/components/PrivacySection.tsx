import React, { useState } from 'react';
import { ShieldCheck, Lock, HardDrive, WifiOff, Eye, RefreshCw, FileCode, CheckCircle, ArrowRight, ToggleLeft, ToggleRight, Info } from 'lucide-react';

interface PrivacySectionProps {
  onOpenPrivacyModal: () => void;
}

export const PrivacySection: React.FC<PrivacySectionProps> = ({ onOpenPrivacyModal }) => {
  const [aiKillSwitch, setAiKillSwitch] = useState(false);
  const [selectedNode, setSelectedNode] = useState<'local' | 'network' | 'user'>('local');

  return (
    <section id="privacy" className="py-24 bg-white relative overflow-hidden">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        
        {/* Header */}
        <div className="text-center max-w-3xl mx-auto space-y-4 mb-16">
          <div className="inline-flex items-center gap-2 px-3.5 py-1.5 rounded-full bg-slate-100 text-slate-800 text-xs font-semibold">
            <Lock className="w-3.5 h-3.5 text-blue-600" />
            100% 数据隐私主权
          </div>
          <h2 className="text-3xl sm:text-4xl font-extrabold text-slate-900 tracking-tight">
            你的输入，首先属于你。
          </h2>
          <p className="text-slate-600 text-base leading-relaxed">
            文字承载着思想、密码、商业机密与私密表达。GY输入法从第一行代码开始，便将“本地优先”写入架构灵魂。
          </p>
        </div>

        {/* Interactive Architecture Flow Diagram */}
        <div className="bg-slate-50 border border-slate-200/80 rounded-3xl p-6 sm:p-10 mb-16 space-y-8 shadow-xs">
          
          <div className="flex flex-col md:flex-row items-center justify-between gap-4 border-b border-slate-200/80 pb-6">
            <div>
              <h3 className="text-xl font-bold text-slate-900 flex items-center gap-2">
                数据流向架构全景图
                <span className="text-xs font-mono font-normal px-2.5 py-0.5 rounded-full bg-blue-50 text-blue-700 border border-blue-200">
                  可审计模型
                </span>
              </h3>
              <p className="text-xs text-slate-500 mt-1">
                点击下方节点，探索数据如何在您的 Windows 本地进行安全闭环
              </p>
            </div>

            {/* Simulated Master AI Switch */}
            <div className="flex items-center gap-3 bg-white p-3 rounded-2xl border border-slate-200/80 shadow-xs">
              <span className="text-xs font-medium text-slate-700">一键硬关停 AI 网络模组:</span>
              <button
                onClick={() => setAiKillSwitch(!aiKillSwitch)}
                className={`flex items-center gap-1.5 px-3 py-1.5 rounded-xl text-xs font-bold transition-all ${
                  aiKillSwitch
                    ? 'bg-rose-100 text-rose-700 border border-rose-300'
                    : 'bg-emerald-100 text-emerald-800 border border-emerald-300'
                }`}
              >
                {aiKillSwitch ? (
                  <>
                    <ToggleLeft className="w-4 h-4 text-rose-600" />
                    已彻底断开 AI 联网
                  </>
                ) : (
                  <>
                    <ToggleRight className="w-4 h-4 text-emerald-600" />
                    正常 (按键触发)
                  </>
                )}
              </button>
            </div>
          </div>

          {/* Graphical Nodes */}
          <div className="grid grid-cols-1 md:grid-cols-3 gap-6 relative">
            
            {/* Node 1: Local Input Core */}
            <div
              onClick={() => setSelectedNode('local')}
              className={`p-6 rounded-2xl border cursor-pointer transition-all relative space-y-4 ${
                selectedNode === 'local'
                  ? 'bg-white border-blue-600 shadow-lg ring-2 ring-blue-600/20'
                  : 'bg-white/80 border-slate-200 hover:border-slate-300'
              }`}
            >
              <div className="flex items-center justify-between">
                <div className="w-10 h-10 rounded-xl bg-blue-50 text-blue-600 flex items-center justify-center">
                  <HardDrive className="w-5 h-5" />
                </div>
                <span className="text-[10px] font-bold font-mono px-2 py-0.5 rounded bg-emerald-50 text-emerald-700 border border-emerald-200">
                  物理隔离
                </span>
              </div>
              <div>
                <h4 className="font-bold text-slate-900 text-base">1. 本地 C++ 核心引擎</h4>
                <p className="text-xs text-slate-500 mt-1 leading-relaxed">
                  所有的按键捕捉、拼音切分、个人词库联想与剪贴板历史记录，全部只在 Windows 本地内存中完成。
                </p>
              </div>
              <div className="text-[11px] font-semibold text-blue-600 flex items-center gap-1 pt-2 border-t border-slate-100">
                状态: 100% 本地闭环
              </div>
            </div>

            {/* Node 2: Optional AI Request */}
            <div
              onClick={() => setSelectedNode('network')}
              className={`p-6 rounded-2xl border cursor-pointer transition-all relative space-y-4 ${
                aiKillSwitch ? 'opacity-50 grayscale' : ''
              } ${
                selectedNode === 'network'
                  ? 'bg-white border-blue-600 shadow-lg ring-2 ring-blue-600/20'
                  : 'bg-white/80 border-slate-200 hover:border-slate-300'
              }`}
            >
              <div className="flex items-center justify-between">
                <div className="w-10 h-10 rounded-xl bg-slate-100 text-slate-700 flex items-center justify-center">
                  <WifiOff className="w-5 h-5" />
                </div>
                <span className={`text-[10px] font-bold font-mono px-2 py-0.5 rounded ${
                  aiKillSwitch ? 'bg-rose-100 text-rose-700' : 'bg-blue-50 text-blue-700'
                }`}>
                  {aiKillSwitch ? '已断开' : '需快捷键触发'}
                </span>
              </div>
              <div>
                <h4 className="font-bold text-slate-900 text-base">2. 可选 AI 增值通道</h4>
                <p className="text-xs text-slate-500 mt-1 leading-relaxed">
                  仅当用户按下 Alt+/ 或点击 AI 按钮时，选中文本才经由 TLS 1.3 传输加密，单次推理后无沉淀销毁。
                </p>
              </div>
              <div className="text-[11px] font-semibold text-slate-600 flex items-center gap-1 pt-2 border-t border-slate-100">
                状态: {aiKillSwitch ? '物理静默' : '待命 (快捷键)'}
              </div>
            </div>

            {/* Node 3: User Total Control */}
            <div
              onClick={() => setSelectedNode('user')}
              className={`p-6 rounded-2xl border cursor-pointer transition-all relative space-y-4 ${
                selectedNode === 'user'
                  ? 'bg-white border-blue-600 shadow-lg ring-2 ring-blue-600/20'
                  : 'bg-white/80 border-slate-200 hover:border-slate-300'
              }`}
            >
              <div className="flex items-center justify-between">
                <div className="w-10 h-10 rounded-xl bg-blue-50 text-blue-600 flex items-center justify-center">
                  <ShieldCheck className="w-5 h-5" />
                </div>
                <span className="text-[10px] font-bold font-mono px-2 py-0.5 rounded bg-blue-50 text-blue-700 border border-blue-200">
                  最高主权
                </span>
              </div>
              <div>
                <h4 className="font-bold text-slate-900 text-base">3. 用户绝对控制极线</h4>
                <p className="text-xs text-slate-500 mt-1 leading-relaxed">
                  随时导出 JSON 词库、一键清除本地历史记录、开启完全离线模式或添加 Windows 防火墙规则。
                </p>
              </div>
              <div className="text-[11px] font-semibold text-blue-600 flex items-center gap-1 pt-2 border-t border-slate-100">
                状态: 完全受控
              </div>
            </div>

          </div>

          {/* Dynamic Node Details Box */}
          <div className="p-5 rounded-2xl bg-white border border-slate-200/80 text-xs text-slate-700 space-y-2 animate-fadeIn">
            {selectedNode === 'local' && (
              <div className="space-y-1">
                <p className="font-bold text-slate-900 text-sm">【详细机制】本地 C++ 引擎与词库安全</p>
                <p className="text-slate-600">
                  您的输入词频分布、长句习惯以及个人导入的专有词汇，默认保存在系统 %APPDATA%\GYShurufa\UserDict.db 中。该文件使用 AES-256 本地密钥加密，未经您的允许，任何程序无法越权读取。
                </p>
              </div>
            )}
            {selectedNode === 'network' && (
              <div className="space-y-1">
                <p className="font-bold text-slate-900 text-sm">【详细机制】AI 传输与隐私屏障</p>
                <p className="text-slate-600">
                  AI 服务运行于 GSYEN 独立安全节点。我们承诺：不上存未选中的字符、不记录 IP 用户画像、不保留原始文本对话日志。一次请求完成即刻物理清除上下文。
                </p>
              </div>
            )}
            {selectedNode === 'user' && (
              <div className="space-y-1">
                <p className="font-bold text-slate-900 text-sm">【详细机制】用户数据擦除与审计</p>
                <p className="text-slate-600">
                  在软件“设置 - 数据管理”中，您可以随时点击“立即物理销毁本地词库”或“导出可读文本”。软件同时支持开启本地日志审计功能，实时记录每一笔调用的毫秒与端口。
                </p>
              </div>
            )}
          </div>

        </div>

        {/* 3 Privacy Pillars */}
        <div className="grid grid-cols-1 sm:grid-cols-3 gap-8 mb-12">
          <div className="p-6 rounded-2xl bg-slate-50 border border-slate-200/60 space-y-3">
            <div className="w-10 h-10 rounded-xl bg-blue-100 text-blue-600 flex items-center justify-center font-bold">
              01
            </div>
            <h3 className="text-lg font-bold text-slate-900">零广告与追踪</h3>
            <p className="text-xs text-slate-500 leading-relaxed">
              绝无任何右下角弹窗新闻、无广告推介、无用户行为数据收集 SDK，还原最安静纯粹的办公打字环境。
            </p>
          </div>

          <div className="p-6 rounded-2xl bg-slate-50 border border-slate-200/60 space-y-3">
            <div className="w-10 h-10 rounded-xl bg-blue-100 text-blue-600 flex items-center justify-center font-bold">
              02
            </div>
            <h3 className="text-lg font-bold text-slate-900">权限极简透明</h3>
            <p className="text-xs text-slate-500 leading-relaxed">
              仅申请 Windows 操作系统 TSF 输入法标准 API 权限。无需管理员特权，不扫描硬盘其他非关文件夹。
            </p>
          </div>

          <div className="p-6 rounded-2xl bg-slate-50 border border-slate-200/60 space-y-3">
            <div className="w-10 h-10 rounded-xl bg-blue-100 text-blue-600 flex items-center justify-center font-bold">
              03
            </div>
            <h3 className="text-lg font-bold text-slate-900">随时可擦除</h3>
            <p className="text-xs text-slate-500 leading-relaxed">
              词库与缓存数据一键清理，卸载时干净不留遗余残留项，完全尊重用户数据主权。
            </p>
          </div>
        </div>

        {/* Bottom CTA to View Whitepaper */}
        <div className="text-center">
          <button
            onClick={onOpenPrivacyModal}
            className="inline-flex items-center justify-center px-6 py-3 rounded-xl bg-slate-900 hover:bg-slate-800 text-white font-medium text-xs sm:text-sm transition-all shadow-md gap-2"
          >
            <ShieldCheck className="w-4 h-4 text-blue-400" />
            阅读完整 GY输入法 隐私白皮书
          </button>
        </div>

      </div>
    </section>
  );
};
