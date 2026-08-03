import { IMESettings, ThemePreset } from '../types';

export interface ThemeDefinition {
  id: ThemePreset;
  name: string;
  nameEn: string;
  settings: Partial<IMESettings>;
  previewColor: string;
}

export const THEME_PRESETS: ThemeDefinition[] = [
  {
    id: 'google-blue',
    name: 'Google 蓝 (Win11 Modern)',
    nameEn: 'Google Blue Modern',
    previewColor: '#2563EB',
    settings: {
      selectedBgColor: '#2563EB',
      selectedTextColor: '#FFFFFF',
      nonSelectedBg: '#FFFFFF',
      textColor: '#0F172A',
      pinyinTextColor: '#64748B',
      numberColor: '#94A3B8',
      selectedNumberColor: '#93C5FD',
      borderColor: '#E2E8F0',
      shadowIntensity: 'subtle',
      fontFamily: 'Segoe UI, "Microsoft YaHei", system-ui, sans-serif',
    },
  },
  {
    id: 'classic-google',
    name: '经典谷歌拼音 (Retro 2008)',
    nameEn: 'Classic Google Pinyin 2008',
    previewColor: '#1A73E8',
    settings: {
      selectedBgColor: '#1A73E8',
      selectedTextColor: '#FFFFFF',
      nonSelectedBg: '#F8FAFC',
      textColor: '#1E293B',
      pinyinTextColor: '#475569',
      numberColor: '#64748B',
      selectedNumberColor: '#BFDBFE',
      borderColor: '#CBD5E1',
      shadowIntensity: 'medium',
      fontFamily: '"SimSun", "Microsoft YaHei", sans-serif',
    },
  },
  {
    id: 'win11-dark',
    name: 'Windows 11 深色模式',
    nameEn: 'Windows 11 Dark Mode',
    previewColor: '#3B82F6',
    settings: {
      selectedBgColor: '#2563EB',
      selectedTextColor: '#FFFFFF',
      nonSelectedBg: '#1E293B',
      textColor: '#F8FAFC',
      pinyinTextColor: '#94A3B8',
      numberColor: '#64748B',
      selectedNumberColor: '#93C5FD',
      borderColor: '#334155',
      shadowIntensity: 'strong',
      fontFamily: 'Segoe UI, "Microsoft YaHei", sans-serif',
    },
  },
  {
    id: 'monokai',
    name: '极客 Monokai 暗黑',
    nameEn: 'Geek Monokai Dark',
    previewColor: '#A6E22E',
    settings: {
      selectedBgColor: '#A6E22E',
      selectedTextColor: '#1E1E1E',
      nonSelectedBg: '#272822',
      textColor: '#F8F8F2',
      pinyinTextColor: '#FD971F',
      numberColor: '#75715E',
      selectedNumberColor: '#3E3D32',
      borderColor: '#3E3D32',
      shadowIntensity: 'medium',
      fontFamily: '"Consolas", "Microsoft YaHei", monospace',
    },
  },
];
