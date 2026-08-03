export type ThemePreset = 'google-blue' | 'classic-google' | 'win11-dark' | 'monokai' | 'custom';
export type DpiScale = 100 | 125 | 150 | 200;
export type EditorTheme = 'notepad' | 'vscode' | 'wechat' | 'word';

export interface IMESettings {
  height: number; // default: 46
  borderRadius: number; // default: 8
  padding: number; // default: 8
  pinyinFontSize: number; // default: 14
  candidateFontSize: number; // default: 18
  maxCandidates: number; // default: 5 (range 3-9)
  maxWidth: number; // default: 640
  selectedBgColor: string; // default: '#2563EB'
  selectedTextColor: string; // default: '#FFFFFF'
  nonSelectedBg: string; // default: '#FFFFFF'
  textColor: string; // default: '#0F172A'
  pinyinTextColor: string; // default: '#64748B'
  numberColor: string; // default: '#94A3B8'
  selectedNumberColor: string; // default: '#93C5FD'
  borderColor: string; // default: '#E2E8F0'
  shadowIntensity: 'none' | 'subtle' | 'medium' | 'strong'; // default: 'subtle'
  dpiScale: DpiScale; // default: 100
  fontFamily: string; // default: 'Segoe UI, "Microsoft YaHei", sans-serif'
  themePreset: ThemePreset;
  showNumbers: boolean; // default: true
  useAiEngine: boolean; // default: false
}

export interface DictionaryEntry {
  pinyin: string;
  candidates: string[];
}

export interface SpecBenchmark {
  label: string;
  value: string;
  description: string;
}
