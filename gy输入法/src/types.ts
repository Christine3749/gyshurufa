export type ThemeMode = 'light' | 'dark' | 'system';
export type InputMode = 'zh' | 'en';
export type PinyinType = 'quanpin' | 'shuangpin';
export type AiTriggerMode = 'off' | 'manual' | 'on';
export type AppView = 'desktop' | 'settings' | 'onboarding';
export type LearningTier = 'none' | 'once' | 'memory' | 'high' | 'fixed';

/**
 * A privacy-safe projection of local IME learning. It contains aggregate
 * counters only; raw keystrokes and unfinished compositions are never part of
 * this contract.
 */
export interface ImeLearningProjection {
  schema: 'gy.ime_learning.v1';
  pinyin: string;
  candidate: string;
  count: number;
  recent7Days: number;
  recent30Days: number;
  activeDays: number;
  pinned: boolean;
  tier: LearningTier;
  updatedAt: string;
}

export type MemoryCardKind = 'word_origin' | 'example' | 'related_words' | 'correction' | 'preference';

/** A user-approved long-term learning card stored independently from Keep clipboard events. */
export interface MemoryCard {
  schema: 'gy.memory_card.v1';
  id: string;
  kind: MemoryCardKind;
  surface: string;
  pinyin?: string;
  meaning?: string;
  origin?: string;
  relatedWords?: string[];
  examples?: string[];
  mnemonic?: string;
  source: 'user' | 'local-learning' | 'ai' | 'keep';
  confidence?: number;
  approved: boolean;
  privacy: 'local-only' | 'account';
  createdAt: string;
  updatedAt: string;
  nextReviewAt?: string;
}

export interface CandidateItem {
  id: number;
  text: string;
  pinyin?: string;
  isPrimary?: boolean;
  frequency?: number;
}

export interface UserSettings {
  general: {
    startOnBoot: boolean;
    defaultLanguage: InputMode;
    shortcutToggle: string;
    showTrayIcon: boolean;
    soundFeedback: boolean;
  };
  input: {
    pinyinType: PinyinType;
    fuzzyPinyin: boolean;
    fuzzyRules: {
      z_zh: boolean;
      c_ch: boolean;
      s_sh: boolean;
      n_l: boolean;
      an_ang: boolean;
      en_eng: boolean;
      in_ing: boolean;
    };
    candidateCount: number; // 5 to 9
    candidateFontSize: number; // 14 to 22
    spaceSelection: boolean; // space to select first candidate
  };
  lexicon: {
    localLearning: boolean;
    clearFrequencyOnExit: boolean;
    cloudSync: boolean; // default false
    userWordsCount: number;
    lastUpdated: string;
  };
  ai: {
    aiMasterToggle: boolean;
    aiTriggerMode: AiTriggerMode;
    aiShortcuts: string;
    onlySelectedText: boolean;
    defaultModel: string;
    temperature: number;
  };
  privacy: {
    localOnlyMode: boolean;
    telemetryData: boolean;
    memoryEncryption: boolean;
    historyLogDays: number;
  };
  security: {
    codeSigningVerified: boolean;
    sandboxExecution: boolean;
    offlineWhitelist: boolean;
  };
  appearance: {
    theme: ThemeMode;
    candidateOpacity: number; // 70 to 100
    candidateFontSize: number;
    cornerRadius: number; // 6 to 16
    accentColor: string; // hex
    fontFamily: string;
  };
  about: {
    appName: string;
    englishName: string;
    brand: string;
    version: string;
    buildNumber: string;
    website: string;
    license: string;
  };
}

export interface AiTaskRequest {
  action: 'polish' | 'rewrite' | 'translate' | 'summarize' | 'reply';
  text: string;
  targetLang?: string;
  context?: string;
}

export interface AiTaskResponse {
  result: string;
  source: string;
  note?: string;
}
