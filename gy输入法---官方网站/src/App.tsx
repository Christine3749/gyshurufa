import React, { useState } from 'react';
import { Navbar } from './components/Navbar';
import { Hero } from './components/Hero';
import { CoreValues } from './components/CoreValues';
import { AIFeatures } from './components/AIFeatures';
import { PrivacySection } from './components/PrivacySection';
import { EcosystemSection } from './components/EcosystemSection';
import { DownloadSection } from './components/DownloadSection';
import { Footer } from './components/Footer';

import { DownloadModal } from './components/modals/DownloadModal';
import { PrivacyModal } from './components/modals/PrivacyModal';
import { AboutGSYENModal } from './components/modals/AboutGSYENModal';
import { ChangelogModal } from './components/modals/ChangelogModal';

export default function App() {
  const [downloadModalOpen, setDownloadModalOpen] = useState(false);
  const [privacyModalOpen, setPrivacyModalOpen] = useState(false);
  const [aboutModalOpen, setAboutModalOpen] = useState(false);
  const [changelogModalOpen, setChangelogModalOpen] = useState(false);

  return (
    <div className="min-h-screen bg-slate-50 text-slate-800 font-sans antialiased selection:bg-blue-600 selection:text-white">
      {/* Top Navbar */}
      <Navbar
        onOpenDownload={() => setDownloadModalOpen(true)}
        onOpenPrivacy={() => setPrivacyModalOpen(true)}
        onOpenAbout={() => setAboutModalOpen(true)}
        onOpenChangelog={() => setChangelogModalOpen(true)}
      />

      {/* Main Page Layout */}
      <main>
        {/* Hero Section */}
        <Hero
          onOpenDownload={() => setDownloadModalOpen(true)}
          onOpenPrivacy={() => setPrivacyModalOpen(true)}
        />

        {/* Core Pillars Section */}
        <CoreValues />

        {/* AI Features Sandbox Section */}
        <AIFeatures />

        {/* Privacy Architecture Section */}
        <PrivacySection
          onOpenPrivacyModal={() => setPrivacyModalOpen(true)}
        />

        {/* GSYEN Ecosystem Section */}
        <EcosystemSection
          onOpenAboutGSYEN={() => setAboutModalOpen(true)}
        />

        {/* Download & Specs Section */}
        <DownloadSection
          onOpenDownloadModal={() => setDownloadModalOpen(true)}
          onOpenChangelogModal={() => setChangelogModalOpen(true)}
        />
      </main>

      {/* Footer */}
      <Footer
        onOpenPrivacyModal={() => setPrivacyModalOpen(true)}
        onOpenAboutGSYEN={() => setAboutModalOpen(true)}
        onOpenChangelogModal={() => setChangelogModalOpen(true)}
      />

      {/* Dialog Modals */}
      <DownloadModal
        isOpen={downloadModalOpen}
        onClose={() => setDownloadModalOpen(false)}
      />

      <PrivacyModal
        isOpen={privacyModalOpen}
        onClose={() => setPrivacyModalOpen(false)}
      />

      <AboutGSYENModal
        isOpen={aboutModalOpen}
        onClose={() => setAboutModalOpen(false)}
      />

      <ChangelogModal
        isOpen={changelogModalOpen}
        onClose={() => setChangelogModalOpen(false)}
      />
    </div>
  );
}
