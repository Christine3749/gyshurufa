import React, { useState, useEffect } from 'react';
import { Download, Shield, Sparkles, Layers, Menu, X, ChevronRight, HardDrive } from 'lucide-react';
import { BRAND_INFO } from '../data/content';

interface NavbarProps {
  onOpenDownload: () => void;
  onOpenPrivacy: () => void;
  onOpenAbout: () => void;
  onOpenChangelog: () => void;
}

export const Navbar: React.FC<NavbarProps> = ({
  onOpenDownload,
  onOpenPrivacy,
  onOpenAbout,
  onOpenChangelog
}) => {
  const [scrolled, setScrolled] = useState(false);
  const [mobileMenuOpen, setMobileMenuOpen] = useState(false);

  useEffect(() => {
    const handleScroll = () => {
      if (window.scrollY > 15) {
        setScrolled(true);
      } else {
        setScrolled(false);
      }
    };
    window.addEventListener('scroll', handleScroll);
    return () => window.removeEventListener('scroll', handleScroll);
  }, []);

  const navLinks = [
    { label: '首页', href: '#hero' },
    { label: '核心优势', href: '#values' },
    { label: 'AI 原生体验', href: '#ai-features' },
    { label: '隐私架构', href: '#privacy' },
    { label: 'GSYEN 生态', href: '#ecosystem' },
    { label: '下载中心', href: '#download' }
  ];

  return (
    <header 
      className={`fixed top-0 left-0 right-0 z-40 transition-all duration-300 ${
        scrolled 
          ? 'bg-white/90 backdrop-blur-md shadow-sm border-b border-slate-200/60 py-3' 
          : 'bg-transparent py-5'
      }`}
    >
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div className="flex items-center justify-between">
          {/* Logo & Brand Identity */}
          <a href="#hero" className="flex items-center gap-3 group">
            <div className="w-9 h-9 rounded-xl bg-blue-600 text-white font-bold flex items-center justify-center text-base shadow-md shadow-blue-500/20 group-hover:bg-blue-700 transition-colors">
              GY
            </div>
            <div className="flex flex-col">
              <div className="flex items-center gap-2">
                <span className="font-bold text-base sm:text-lg text-slate-900 tracking-tight">
                  GY输入法
                </span>
                <span className="text-[10px] font-semibold px-1.5 py-0.2 rounded bg-slate-100 text-slate-600 border border-slate-200">
                  GSYEN
                </span>
              </div>
              <span className="text-[11px] text-slate-400 -mt-0.5 hidden sm:inline-block">
                shurufa.wang
              </span>
            </div>
          </a>

          {/* Desktop Navigation */}
          <nav className="hidden lg:flex items-center gap-1 bg-slate-100/70 p-1 rounded-full border border-slate-200/50 backdrop-blur-sm">
            {navLinks.map((link) => (
              <a
                key={link.label}
                href={link.href}
                className="px-4 py-1.5 rounded-full text-xs font-medium text-slate-600 hover:text-slate-900 hover:bg-white transition-all"
              >
                {link.label}
              </a>
            ))}
            <button
              onClick={onOpenAbout}
              className="px-3.5 py-1.5 rounded-full text-xs font-medium text-slate-600 hover:text-blue-600 hover:bg-white transition-all flex items-center gap-1"
            >
              关于 GSYEN
            </button>
          </nav>

          {/* Header Action Controls */}
          <div className="hidden sm:flex items-center gap-3">
            <button
              onClick={onOpenPrivacy}
              className="text-xs font-medium text-slate-600 hover:text-blue-600 transition-colors px-3 py-2 flex items-center gap-1.5"
            >
              <Shield className="w-3.5 h-3.5 text-blue-600" />
              隐私策略
            </button>

            <button
              onClick={onOpenDownload}
              className="inline-flex items-center justify-center px-4 py-2 rounded-xl bg-blue-600 hover:bg-blue-700 text-white font-medium text-xs shadow-md shadow-blue-600/15 transition-all gap-1.5 active:scale-95"
            >
              <Download className="w-3.5 h-3.5" />
              下载 Windows 版
            </button>
          </div>

          {/* Mobile Toggle Button */}
          <div className="flex sm:hidden items-center gap-2">
            <button
              onClick={onOpenDownload}
              className="px-3 py-1.5 rounded-lg bg-blue-600 text-white text-xs font-medium shadow-sm"
            >
              下载
            </button>
            <button
              onClick={() => setMobileMenuOpen(!mobileMenuOpen)}
              className="p-2 rounded-lg text-slate-600 hover:bg-slate-100 transition-colors"
              aria-label="切换菜单"
            >
              {mobileMenuOpen ? <X className="w-5 h-5" /> : <Menu className="w-5 h-5" />}
            </button>
          </div>
        </div>
      </div>

      {/* Mobile Drawer Menu */}
      {mobileMenuOpen && (
        <div className="sm:hidden bg-white/95 backdrop-blur-xl border-b border-slate-200 px-4 py-5 space-y-3 animate-fadeIn shadow-lg">
          <div className="space-y-1">
            {navLinks.map((link) => (
              <a
                key={link.label}
                href={link.href}
                onClick={() => setMobileMenuOpen(false)}
                className="block px-3 py-2 rounded-lg text-sm font-medium text-slate-700 hover:bg-slate-100 transition-colors"
              >
                {link.label}
              </a>
            ))}
          </div>

          <div className="pt-3 border-t border-slate-100 space-y-2">
            <button
              onClick={() => { setMobileMenuOpen(false); onOpenPrivacy(); }}
              className="w-full text-left px-3 py-2 rounded-lg text-sm text-slate-600 hover:bg-slate-100 flex items-center justify-between"
            >
              <span className="flex items-center gap-2">
                <Shield className="w-4 h-4 text-blue-600" />
                了解隐私设计白皮书
              </span>
              <ChevronRight className="w-4 h-4 text-slate-400" />
            </button>

            <button
              onClick={() => { setMobileMenuOpen(false); onOpenAbout(); }}
              className="w-full text-left px-3 py-2 rounded-lg text-sm text-slate-600 hover:bg-slate-100 flex items-center justify-between"
            >
              <span className="flex items-center gap-2">
                <Layers className="w-4 h-4 text-slate-600" />
                关于母品牌 GSYEN
              </span>
              <ChevronRight className="w-4 h-4 text-slate-400" />
            </button>

            <button
              onClick={() => { setMobileMenuOpen(false); onOpenChangelog(); }}
              className="w-full text-left px-3 py-2 rounded-lg text-sm text-slate-600 hover:bg-slate-100 flex items-center justify-between"
            >
              <span className="flex items-center gap-2">
                <HardDrive className="w-4 h-4 text-slate-600" />
                查看更新日志 ({BRAND_INFO.version})
              </span>
              <ChevronRight className="w-4 h-4 text-slate-400" />
            </button>
          </div>
        </div>
      )}
    </header>
  );
};
