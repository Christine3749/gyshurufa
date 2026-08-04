import React from 'react';
import { Mail, Globe, Shield, ExternalLink, Heart } from 'lucide-react';
import { BRAND_INFO } from '../data/content';

interface FooterProps {
  onOpenPrivacyModal: () => void;
  onOpenAboutGSYEN: () => void;
  onOpenChangelogModal: () => void;
}

export const Footer: React.FC<FooterProps> = ({
  onOpenPrivacyModal,
  onOpenAboutGSYEN,
  onOpenChangelogModal
}) => {
  return (
    <footer className="bg-slate-900 text-slate-400 text-xs border-t border-slate-800">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-12">
        
        <div className="grid grid-cols-1 md:grid-cols-12 gap-8 mb-12">
          
          {/* Brand & Slogan */}
          <div className="md:col-span-5 space-y-4">
            <div className="flex items-center gap-3">
              <div className="w-8 h-8 rounded-xl bg-blue-600 text-white font-bold flex items-center justify-center text-sm">
                GY
              </div>
              <div className="flex items-center gap-2">
                <span className="font-bold text-base text-white">GY输入法</span>
                <span className="text-[10px] px-1.5 py-0.5 rounded bg-slate-800 text-slate-300 border border-slate-700">
                  GSYEN
                </span>
              </div>
            </div>

            <p className="text-slate-400 text-xs leading-relaxed max-w-sm">
              {BRAND_INFO.slogan}<br />
              {BRAND_INFO.subSlogan}
            </p>

            <div className="flex items-center gap-2 text-slate-500 font-mono text-[11px]">
              <Globe className="w-3.5 h-3.5 text-blue-400" />
              <span>官方域名：<strong className="text-slate-300">{BRAND_INFO.domain}</strong></span>
            </div>
          </div>

          {/* Quick Links Column 1 */}
          <div className="md:col-span-3 space-y-3">
            <h4 className="font-bold text-white text-sm">产品与服务</h4>
            <ul className="space-y-2">
              <li>
                <a href="#hero" className="hover:text-white transition-colors">GY输入法 Windows 版</a>
              </li>
              <li>
                <a href="#values" className="hover:text-white transition-colors">离线拼音引擎</a>
              </li>
              <li>
                <a href="#ai-features" className="hover:text-white transition-colors">AI 改写与润色</a>
              </li>
              <li>
                <button onClick={onOpenChangelogModal} className="hover:text-white transition-colors text-left">
                  版本更新日志
                </button>
              </li>
            </ul>
          </div>

          {/* Quick Links Column 2 */}
          <div className="md:col-span-4 space-y-3">
            <h4 className="font-bold text-white text-sm">隐私与合规</h4>
            <ul className="space-y-2">
              <li>
                <button onClick={onOpenPrivacyModal} className="hover:text-white transition-colors text-left flex items-center gap-1">
                  <Shield className="w-3.5 h-3.5 text-blue-400" />
                  隐私政策与本地优先承诺
                </button>
              </li>
              <li>
                <button onClick={onOpenAboutGSYEN} className="hover:text-white transition-colors text-left">
                  关于母品牌 GSYEN 生态
                </button>
              </li>
              <li className="pt-2 text-slate-400 flex items-center gap-1">
                <Mail className="w-3.5 h-3.5 text-slate-400" />
                官方联系邮箱：<a href="mailto:contact@gsyen.com" className="text-blue-400 hover:underline">contact@gsyen.com</a>
              </li>
            </ul>
          </div>

        </div>

        {/* Bottom Bar */}
        <div className="pt-8 border-t border-slate-800/80 flex flex-col sm:flex-row items-center justify-between gap-4 text-slate-500 text-[11px]">
          <div>
            Copyright © 2026 GSYEN. All Rights Reserved. 保留所有权利。
          </div>

          <div className="flex items-center gap-4">
            <button onClick={onOpenPrivacyModal} className="hover:text-slate-300">
              隐私白皮书
            </button>
            <span>•</span>
            <button onClick={onOpenAboutGSYEN} className="hover:text-slate-300">
              GSYEN 官方条款
            </button>
            <span>•</span>
            <span className="text-slate-400">Windows 10 / 11 专享</span>
          </div>
        </div>

      </div>
    </footer>
  );
};
