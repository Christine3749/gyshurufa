import React, { useState, useEffect } from 'react';
import { UserSettings } from './types';
import { loadUserSettings, saveUserSettings } from './lib/settingsState';
import { DesktopSimulator } from './components/DesktopSimulator';

export default function App() {
  const [settings, setSettings] = useState<UserSettings>(loadUserSettings());

  // Save settings on update
  const handleUpdateSettings = (updater: (prev: UserSettings) => UserSettings) => {
    setSettings((prev) => {
      const updated = updater(prev);
      saveUserSettings(updated);
      return updated;
    });
  };

  // Sync theme attribute with html element for Tailwind dark mode
  useEffect(() => {
    const isDark =
      settings.appearance.theme === 'dark' ||
      (settings.appearance.theme === 'system' &&
        window.matchMedia('(prefers-color-scheme: dark)').matches);

    if (isDark) {
      document.documentElement.classList.add('dark');
    } else {
      document.documentElement.classList.remove('dark');
    }
  }, [settings.appearance.theme]);

  return (
    <DesktopSimulator
      settings={settings}
      onUpdateSettings={handleUpdateSettings}
    />
  );
}
