import { UserSettings } from '../types';

export const DEFAULT_SETTINGS: UserSettings = {
  general: {
    startOnBoot: true,
    defaultLanguage: 'zh',
    shortcutToggle: 'Shift',
    showTrayIcon: true,
    soundFeedback: false,
  },
  input: {
    pinyinType: 'quanpin',
    fuzzyPinyin: false,
    fuzzyRules: {
      z_zh: true,
      c_ch: true,
      s_sh: true,
      n_l: false,
      an_ang: true,
      en_eng: false,
      in_ing: false,
    },
    candidateCount: 5,
    candidateFontSize: 16,
    spaceSelection: true,
  },
  lexicon: {
    localLearning: true,
    clearFrequencyOnExit: false,
    cloudSync: false,
    userWordsCount: 1420,
    lastUpdated: '2026-08-01 11:30',
  },
  ai: {
    aiMasterToggle: true,
    aiTriggerMode: 'manual', // 仅手动触发
    aiShortcuts: 'Ctrl + Shift + A',
    onlySelectedText: true,
    defaultModel: 'gemini-2.5-flash',
    temperature: 0.7,
  },
  privacy: {
    localOnlyMode: true,
    telemetryData: false,
    memoryEncryption: true,
    historyLogDays: 30,
  },
  security: {
    codeSigningVerified: false,
    sandboxExecution: true,
    offlineWhitelist: true,
  },
  appearance: {
    theme: 'light',
    candidateOpacity: 95,
    candidateFontSize: 16,
    cornerRadius: 10,
    accentColor: '#1D4ED8', // GSYEN Blue
    fontFamily: 'Microsoft YaHei UI, Segoe UI, sans-serif',
  },
  about: {
    appName: 'GY输入法',
    englishName: 'GY Shurufa',
    brand: 'GSYEN',
    version: '2.5.0-Release',
    buildNumber: '20260801.1042',
    website: 'shurufa.wang',
    license: 'GSYEN Proprietary License',
  },
};

const STORAGE_KEY = 'gy_shurufa_user_settings_v2';

export function loadUserSettings(): UserSettings {
  try {
    const saved = localStorage.getItem(STORAGE_KEY);
    if (saved) {
      return { ...DEFAULT_SETTINGS, ...JSON.parse(saved) };
    }
  } catch (e) {
    console.warn('Failed to load settings from localStorage', e);
  }
  return DEFAULT_SETTINGS;
}

export function saveUserSettings(settings: UserSettings): void {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(settings));
  } catch (e) {
    console.warn('Failed to save settings to localStorage', e);
  }
}
