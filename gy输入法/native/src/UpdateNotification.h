#pragma once

#include <string>

// Shows one Windows Toast for a verified newer GY release. The notification
// itself never downloads or installs anything; its protocol actions are
// handled by the packaged AutoUpdate-GYInput.ps1 entry point.
bool ShowGyUpdateNotification(const std::wstring& version);
