import { useMemo } from 'react';

export type UserPlatform = 'windows' | 'macos' | 'other';

// 识别访客设备：Windows 访客给 .exe，Mac 访客给 Apple Silicon .pkg。
// userAgentData 优先，UA/platform 兜底；识别不了归 other（展示通用下载入口）。
export function useUserPlatform(): UserPlatform {
  return useMemo(() => {
    if (typeof navigator === 'undefined') return 'other';
    const nav = navigator as Navigator & { userAgentData?: { platform?: string } };
    const sources = [
      nav.userAgentData?.platform ?? '',
      navigator.platform ?? '',
      navigator.userAgent ?? ''
    ].join(' ').toLowerCase();
    if (/mac|darwin/.test(sources)) return 'macos';
    if (/win/.test(sources)) return 'windows';
    return 'other';
  }, []);
}
