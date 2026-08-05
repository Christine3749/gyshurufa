#pragma once

// 本机剪贴板历史（CLIPBOARD-PAGE-DESIGN.md §4 数据契约）：
// 保留最近 20 条、先进后出、单条最大 1 MiB、一期纯文字。
// 全部由 GyImeHost 进程本地读写，零网络；设置面板与监听窗口同进程共享。

#include <string>
#include <vector>

namespace gy::clipboard_history {

struct Entry {
  unsigned long long unix_time = 0;
  std::wstring text;
};

constexpr size_t kMaxEntries = 20;
constexpr size_t kMaxItemBytes = 1048576;  // 1 MiB（按 UTF-8 字节计）

// %LOCALAPPDATA%\GYInput\clipboard-history.tsv
std::wstring HistoryPath();

// 新条目在前（index 0 = 最新）。文件缺失或损坏时返回空。
std::vector<Entry> ReadAll();

// 从系统剪贴板读取 CF_UNICODETEXT 并追加一条。
// 跳过：非文本、空文本、超过 1 MiB、与最新一条重复、
// 以及密码管理器等标记了“不要进历史”的敏感内容。
// 返回 true 表示历史发生了变化。
bool AppendFromClipboard();

// 删除整个历史文件。
bool Clear();

// 当前条目数（ReadAll 的便捷封装）。
size_t Count();

}  // namespace gy::clipboard_history
