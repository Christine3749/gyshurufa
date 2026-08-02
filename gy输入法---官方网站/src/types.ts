export interface CandidateItem {
  id: number;
  word: string;
  pinyin?: string;
  tag?: string;
  frequency?: string;
  description?: string;
}

export interface TypingScenario {
  id: string;
  label: string;
  pinyinInput: string;
  rawInputDisplay: string;
  candidates: CandidateItem[];
  aiSuggestion?: {
    type: 'polish' | 'translate' | 'snippet' | 'summary';
    title: string;
    original: string;
    result: string;
  };
}

export interface AIFeatureCard {
  id: string;
  iconName: string;
  title: string;
  subtitle: string;
  description: string;
  triggerKey: string;
  exampleOriginal: string;
  exampleProcessed: string;
  tag: string;
}

export interface EcosystemModule {
  id: string;
  name: string;
  category: string;
  description: string;
  accentColor: string;
  status: string;
}

export interface VersionInfo {
  version: string;
  date: string;
  channel: string;
  size: string;
  architecture: string;
  sha256: string;
  highlights: string[];
}
