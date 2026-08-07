#pragma once

namespace gy::keep_sync {

// Starts the single background worker that projects Keep's newest clipboard
// captures into the local 20-entry history and Windows clipboard.
void Start();
void Stop();

// Wake the worker immediately after a local copy or an account transition.
void NotifyLocalClipboardChanged();
void NotifyAccountChanged();

// Settings-page controls. Disabled keeps the local history offline; Instant
// Paste controls whether a freshly received Keep record becomes Windows'
// current system clipboard.
void SetEnabled(bool enabled);
void SetInstantPasteEnabled(bool enabled);

}  // namespace gy::keep_sync
