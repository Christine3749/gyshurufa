import { useEffect, useState } from 'react';

type RawReleasePlatform = Partial<ReleasePlatform> & {
  filename?: string;
  setupFile?: string;
  packageFile?: string;
  available?: boolean;
};

const RELEASE_WORKER_ORIGIN = 'https://gy-shurufa-download.lihouyi7586.workers.dev';

export type ReleasePlatform = {
  version: string;
  platform: 'windows' | 'macos';
  architecture: string;
  filename: string;
  bytes: number;
  sha256: string;
  state: string;
  signed?: boolean;
  notarized?: boolean;
  downloadUrl: string;
  sha256Url: string;
  available: boolean;
};

export type ReleaseStatus = {
  releaseId: string;
  channel: string;
  publishedAtUtc?: string;
  releaseStatus?: string;
  platforms: {
    windows: ReleasePlatform;
    macos: ReleasePlatform;
  };
};

function resolveReleaseUrl(value?: string): string {
  if (!value) return '';
  if (value.startsWith('http://') || value.startsWith('https://')) return value;
  return value.startsWith('/') ? `${RELEASE_WORKER_ORIGIN}${value}` : value;
}

type LegacyPayload = {
  version?: string;
  coreVersion?: string;
  hostVersion?: string;
  releaseId?: string;
  channel?: string;
  publishedAtUtc?: string;
  windows?: RawReleasePlatform;
  macos?: RawReleasePlatform;
  platforms?: {
    windows?: RawReleasePlatform;
    macos?: RawReleasePlatform;
  };
  service?: string;
};

const VERIFIED_STATES = new Set(['candidate', 'signed', 'notarized', 'stable']);
const SHA256_PATTERN = /^[a-fA-F0-9]{64}$/;
const ZERO_SHA256 = /^0{64}$/;

function hasUsableSha(value?: string): boolean {
  return SHA256_PATTERN.test(value ?? '') && !ZERO_SHA256.test(value ?? '');
}

function hasVerifiedState(value?: string): boolean {
  return typeof value === 'string' && VERIFIED_STATES.has(value);
}


export function formatReleaseBytes(bytes?: number): string {
  if (!bytes || bytes <= 0) return '验证中';
  return `${(bytes / 1024 / 1024).toFixed(2)} MB`;
}

export function formatReleaseDate(value?: string): string {
  if (!value) return '验证中';
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return '验证中';
  return new Intl.DateTimeFormat('zh-CN', { year: 'numeric', month: 'long', day: 'numeric' }).format(date);
}

function sanitizePlatform(value: RawReleasePlatform | undefined, platform: 'windows' | 'macos', fallbackVersion: string): ReleasePlatform {
  const isWindows = platform === 'windows';
  const filename =
    value?.filename ??
    (isWindows ? value?.setupFile : value?.packageFile) ??
    (isWindows ? `GYInputSetup-${fallbackVersion}.exe` : `GYInput-${fallbackVersion}-arm64.pkg`);

  return {
    version: value?.version ?? fallbackVersion,
    platform,
    architecture: value?.architecture ?? (isWindows ? 'x64' : 'arm64'),
    filename,
    bytes: value?.bytes ?? 0,
    sha256: value?.sha256 ?? '',
    state: value?.state ?? 'verification-required',
    signed: value?.signed,
    notarized: value?.notarized,
    downloadUrl: resolveReleaseUrl(value?.downloadUrl),
    sha256Url: resolveReleaseUrl(value?.sha256Url),
    available:
      value?.available ??
      (hasVerifiedState(value?.state) && hasUsableSha(value?.sha256)),
  };
}

export function useReleaseStatus() {
  const [release, setRelease] = useState<ReleaseStatus | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const controller = new AbortController();
    void fetch('/api/releases/latest', {
      headers: { accept: 'application/json' },
      cache: 'no-store',
      signal: controller.signal
    })
      .then(async (response) => {
        if (!response.ok) throw new Error(`release status ${response.status}`);
        const value = (await response.json()) as LegacyPayload;

        const platforms = value.platforms;
        const candidateWindows = platforms?.windows || value.windows;
        const candidateMacos = platforms?.macos || value.macos;
        const windowsVersion = value.version || candidateWindows?.version || '0.0.0';

        if (!candidateWindows) {
          throw new Error('release status is incomplete');
        }

        const effectiveMacosVersion = candidateMacos?.version || windowsVersion;

        setRelease({
          releaseId: value.releaseId ?? `legacy-${windowsVersion}`,
          channel: value.channel ?? 'candidate',
          publishedAtUtc: value.publishedAtUtc,
          platforms: {
            windows: sanitizePlatform(candidateWindows, 'windows', windowsVersion),
            macos: sanitizePlatform(
              {
                ...candidateMacos,
                state: candidateMacos?.state ?? 'verification-required',
                architecture: candidateMacos?.architecture ?? 'arm64',
                version: candidateMacos?.version ?? effectiveMacosVersion,
                filename: candidateMacos?.filename || candidateMacos?.packageFile || `GYInput-${effectiveMacosVersion}-arm64.pkg`,
              },
              'macos',
              effectiveMacosVersion
            ),
          },
        });
      })
      .catch(() => setRelease(null))
      .finally(() => setLoading(false));

    return () => controller.abort();
  }, []);

  return { release, loading };
}

