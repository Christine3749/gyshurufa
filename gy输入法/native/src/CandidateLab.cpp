#include "CandidateWindow.h"
#include "CandidateAppearancePolicy.h"
#include "EnglishLexicon.h"
#include "PinyinEngine.h"

#include <windows.h>

#include <algorithm>
#include <memory>
#include <string>
#include <vector>

namespace {

constexpr wchar_t kWindowClass[] = L"GyCandidateLabWindow";
constexpr wchar_t kOwnerProperty[] = L"GYCandidateLabOwner";
constexpr wchar_t kPreviousProcProperty[] = L"GYCandidateLabPreviousProc";
constexpr int kInputId = 100;
constexpr int kOutputId = 101;
constexpr int kEnglishButtonId = 110;
constexpr int kSimplifiedButtonId = 111;
constexpr int kTraditionalButtonId = 112;

bool PreviewExpanded() {
  wchar_t value[8]{};
  const DWORD length = GetEnvironmentVariableW(
      L"GYINPUT_CANDIDATE_LAB_EXPANDED", value, static_cast<DWORD>(std::size(value)));
  return length > 0 && length < std::size(value) && value[0] == L'1';
}

int PreviewMode() {
  wchar_t value[8]{};
  const DWORD length = GetEnvironmentVariableW(
      L"GYINPUT_CANDIDATE_LAB_INITIAL_MODE", value, static_cast<DWORD>(std::size(value)));
  return length > 0 && length < std::size(value) && value[0] >= L'0' && value[0] <= L'2'
      ? static_cast<int>(value[0] - L'0') : 2;
}

int PreviewScalePercent() {
  wchar_t value[8]{};
  const DWORD length = GetEnvironmentVariableW(
      L"GYINPUT_CANDIDATE_LAB_SCALE", value, static_cast<DWORD>(std::size(value)));
  if (length > 0 && length < std::size(value)) {
    if (value[0] == L'0') return gy::candidate_appearance::kAutoScalePreference;
    if (value[0] == L'9' && value[1] == L'5') return 95;
  }
  return 100;
}

std::wstring ModuleDirectory() {
  wchar_t path[MAX_PATH]{};
  const DWORD length = GetModuleFileNameW(nullptr, path, MAX_PATH);
  if (length == 0 || length >= MAX_PATH) return {};
  std::wstring result(path, length);
  const size_t slash = result.find_last_of(L"\\/");
  return slash == std::wstring::npos ? L"." : result.substr(0, slash);
}

std::wstring PreviewLocalAppData() {
  wchar_t temporary[MAX_PATH]{};
  const DWORD length = GetTempPathW(MAX_PATH, temporary);
  if (length == 0 || length >= MAX_PATH) return {};
  return std::wstring(temporary, length) + L"GY-CandidateLab-" +
         std::to_wstring(GetCurrentProcessId());
}

bool IsEnglishPunctuation(wchar_t character) {
  switch (character) {
    case L'.': case L',': case L';': case L':': case L'!': case L'?':
    case L'(': case L')': case L'[': case L']': case L'{': case L'}':
    case L'\'': case L'\"': case L'-': case L'_': case L'/': case L'\\':
      return true;
    default:
      return false;
  }
}

class CandidateLab {
 public:
  CandidateLab()
      : candidate_window_([this](unsigned action) { return Choose(action); },
                          [](const RECT&) {}) {}

  int Run(HINSTANCE instance, int show_command) {
    preview_local_app_data_ = PreviewLocalAppData();
    if (preview_local_app_data_.empty()) return 10;
    CreateDirectoryW(preview_local_app_data_.c_str(), nullptr);
    SetEnvironmentVariableW(L"LOCALAPPDATA", preview_local_app_data_.c_str());
    const std::wstring settings_directory = preview_local_app_data_ + L"\\GYInput";
    CreateDirectoryW(settings_directory.c_str(), nullptr);
    const std::wstring settings_path = settings_directory + L"\\settings.ini";
    WritePrivateProfileStringW(L"Appearance", L"CandidateScale",
                               std::to_wstring(PreviewScalePercent()).c_str(),
                               settings_path.c_str());
    SetEnvironmentVariableW(L"GYINPUT_CANDIDATE_LAB_MODE", L"2");
    engine_ = std::make_unique<PinyinEngine>(ModuleDirectory());
    gy::english_lexicon::RefreshVerifiedSnapshot();

    WNDCLASSEXW window_class{sizeof(window_class)};
    window_class.hInstance = instance;
    window_class.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    window_class.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
    window_class.lpfnWndProc = WindowProc;
    window_class.lpszClassName = kWindowClass;
    if (!RegisterClassExW(&window_class) && GetLastError() != ERROR_CLASS_ALREADY_EXISTS) return 11;

    hwnd_ = CreateWindowExW(0, kWindowClass, L"GY 候选实验室（隔离预览）",
                            WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX,
                            CW_USEDEFAULT, CW_USEDEFAULT, 760, 440, nullptr, nullptr, instance, this);
    if (!hwnd_) return 12;
    ShowWindow(hwnd_, show_command);
    UpdateWindow(hwnd_);

    MSG message{};
    while (GetMessageW(&message, nullptr, 0, 0) > 0) {
      TranslateMessage(&message);
      DispatchMessageW(&message);
    }
    return static_cast<int>(message.wParam);
  }

 private:
  static LRESULT CALLBACK WindowProc(HWND window, UINT message, WPARAM wparam, LPARAM lparam) {
    auto* self = reinterpret_cast<CandidateLab*>(GetWindowLongPtrW(window, GWLP_USERDATA));
    if (message == WM_NCCREATE) {
      self = reinterpret_cast<CandidateLab*>(reinterpret_cast<CREATESTRUCTW*>(lparam)->lpCreateParams);
      SetWindowLongPtrW(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
    }
    if (!self) return DefWindowProcW(window, message, wparam, lparam);
    switch (message) {
      case WM_CREATE:
        // CreateWindowEx has not returned to Run() yet, so assign the native
        // window before creating child controls that need it as their parent.
        self->hwnd_ = window;
        return self->CreateControls() ? 0 : -1;
      case WM_COMMAND:
        self->HandleCommand(LOWORD(wparam), HIWORD(wparam));
        return 0;
      case WM_DESTROY:
        self->candidate_window_.Hide();
        PostQuitMessage(0);
        return 0;
      default:
        return DefWindowProcW(window, message, wparam, lparam);
    }
  }

  static LRESULT CALLBACK InputProc(HWND window, UINT message, WPARAM wparam, LPARAM lparam) {
    auto* self = reinterpret_cast<CandidateLab*>(GetPropW(window, kOwnerProperty));
    auto previous = reinterpret_cast<WNDPROC>(GetPropW(window, kPreviousProcProperty));
    if (self && message == WM_KEYDOWN && self->HandleKey(wparam)) return 0;
    if (self && message == WM_CHAR && self->HandleCharacter(static_cast<wchar_t>(wparam))) return 0;
    if (message == WM_NCDESTROY) {
      RemovePropW(window, kOwnerProperty);
      RemovePropW(window, kPreviousProcProperty);
    }
    return previous ? CallWindowProcW(previous, window, message, wparam, lparam)
                    : DefWindowProcW(window, message, wparam, lparam);
  }

  bool CreateControls() {
    font_ = CreateFontW(-20, 0, 0, 0, FW_SEMIBOLD, FALSE, FALSE, FALSE, DEFAULT_CHARSET,
                        OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
                        DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI");
    body_font_ = CreateFontW(-16, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE, DEFAULT_CHARSET,
                             OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
                             DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI");
    const auto make_static = [this](const wchar_t* text, int x, int y, int width, int height, int id) {
      HWND control = CreateWindowExW(0, L"STATIC", text, WS_CHILD | WS_VISIBLE,
                                     x, y, width, height, hwnd_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(id)), nullptr, nullptr);
      SendMessageW(control, WM_SETFONT, reinterpret_cast<WPARAM>(body_font_), TRUE);
      return control;
    };
    HWND title = make_static(L"候选输入体验 · 隔离预览", 28, 22, 630, 30, 1);
    SendMessageW(title, WM_SETFONT, reinterpret_cast<WPARAM>(font_), TRUE);
    make_static(L"不会安装、注册或改写当前 GY 输入法。先在这里确认候选样式和选择逻辑。", 28, 58, 680, 24, 2);

    english_button_ = CreateWindowExW(0, L"BUTTON", L"EN 英文候选", WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
                                      28, 98, 150, 38, hwnd_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kEnglishButtonId)), nullptr, nullptr);
    simplified_button_ = CreateWindowExW(0, L"BUTTON", L"简体 · 中英混打", WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
                                         188, 98, 170, 38, hwnd_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kSimplifiedButtonId)), nullptr, nullptr);
    traditional_button_ = CreateWindowExW(0, L"BUTTON", L"繁体 · 中英混打", WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
                                          368, 98, 170, 38, hwnd_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kTraditionalButtonId)), nullptr, nullptr);
    for (HWND button : {english_button_, simplified_button_, traditional_button_}) {
      SendMessageW(button, WM_SETFONT, reinterpret_cast<WPARAM>(body_font_), TRUE);
    }

    make_static(L"输入测试", 28, 155, 100, 24, 3);
    input_ = CreateWindowExW(WS_EX_CLIENTEDGE, L"EDIT", L"", WS_CHILD | WS_VISIBLE | ES_AUTOHSCROLL,
                             28, 182, 685, 38, hwnd_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kInputId)), nullptr, nullptr);
    SendMessageW(input_, WM_SETFONT, reinterpret_cast<WPARAM>(font_), TRUE);
    SetPropW(input_, kOwnerProperty, reinterpret_cast<HANDLE>(this));
    const auto previous = reinterpret_cast<WNDPROC>(SetWindowLongPtrW(input_, GWLP_WNDPROC,
                                                                        reinterpret_cast<LONG_PTR>(InputProc)));
    SetPropW(input_, kPreviousProcProperty, reinterpret_cast<HANDLE>(previous));

    guidance_ = make_static(L"在 EN 输入 wo：固定横向最多 5 个；左右键选择，Tab 接受；数字、上下键不选词。", 28, 236, 690, 24, 4);
    make_static(L"实验输出", 28, 278, 100, 24, 5);
    output_ = CreateWindowExW(WS_EX_CLIENTEDGE, L"EDIT", L"", WS_CHILD | WS_VISIBLE | ES_MULTILINE |
                              ES_AUTOVSCROLL | ES_READONLY | WS_VSCROLL,
                              28, 304, 685, 74, hwnd_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kOutputId)), nullptr, nullptr);
    SendMessageW(output_, WM_SETFONT, reinterpret_cast<WPARAM>(body_font_), TRUE);

    SetMode(PreviewMode());
    expanded_ = PreviewExpanded();
    wchar_t initial_query[65]{};
    const DWORD initial_query_length = GetEnvironmentVariableW(
        L"GYINPUT_CANDIDATE_LAB_QUERY", initial_query,
        static_cast<DWORD>(std::size(initial_query)));
    if (initial_query_length > 0 && initial_query_length < std::size(initial_query)) {
      SetWindowTextW(input_, initial_query);
      RenderCandidates();
    }
    SetFocus(input_);
    return input_ && output_ && guidance_;
  }

  void HandleCommand(int id, int notification) {
    if (id == kEnglishButtonId) return SetMode(2);
    if (id == kSimplifiedButtonId) return SetMode(0);
    if (id == kTraditionalButtonId) return SetMode(1);
    if (id == kInputId && notification == EN_CHANGE) RenderCandidates();
  }

  void SetMode(int value) {
    mode_ = value;
    SetEnvironmentVariableW(L"GYINPUT_CANDIDATE_LAB_MODE", std::to_wstring(mode_).c_str());
    SendMessageW(english_button_, BM_SETSTATE, mode_ == 2, 0);
    SendMessageW(simplified_button_, BM_SETSTATE, mode_ == 0, 0);
    SendMessageW(traditional_button_, BM_SETSTATE, mode_ == 1, 0);
    const wchar_t* guidance = mode_ == 2
        ? L"在 EN 输入 wo：固定横向最多 5 个；左右键选择，Tab 接受；数字、上下键不选词。"
        : mode_ == 0
        ? L"输入 like、blue：英文原词在第 1 项；输入 wolike：第 1 项应为“我 like”。"
        : L"输入 nihao：候选应为繁体；输入 like：英文原词仍应排在第 1 项。";
    SetWindowTextW(guidance_, guidance);
    selected_ = 0;
    expanded_ = false;
    RenderCandidates();
    SetFocus(input_);
  }

  std::wstring InputText() const {
    const int length = GetWindowTextLengthW(input_);
    if (length <= 0) return {};
    std::wstring text(static_cast<size_t>(length) + 1, L'\0');
    GetWindowTextW(input_, text.data(), length + 1);
    text.resize(static_cast<size_t>(length));
    return text;
  }

  void RenderCandidates() {
    const std::wstring query = InputText();
    if (query.empty()) {
      candidates_.clear();
      candidate_window_.Hide();
      return;
    }
    if (mode_ == 2) {
      candidates_ = gy::english_lexicon::PrefixMatches(
          query, CandidateWindow::kExpandedEnglishCandidates);
    } else if (engine_ && engine_->IsReady()) {
      candidates_ = engine_->Lookup(query, mode_);
    } else {
      candidates_.clear();
    }
    if (candidates_.empty()) {
      candidate_window_.Hide();
      return;
    }
    selected_ = std::min<unsigned>(selected_, static_cast<unsigned>(candidates_.size() - 1));
    RECT input_rect{};
    GetWindowRect(input_, &input_rect);
    const RECT anchor{input_rect.left + 8, input_rect.top, input_rect.right, input_rect.bottom};
    const unsigned purpose = mode_ == 2 ? 1u : 0u;
    candidate_window_.Show(anchor, query, candidates_, selected_, 0, mode_, purpose,
                           mode_ == 2 ? false : expanded_, mode_ == 2 ? expanded_ : false,
                           mode_ == 2 && expanded_);
  }

  bool HandleKey(WPARAM key) {
    if (key == VK_ESCAPE) {
      SetWindowTextW(input_, L"");
      return true;
    }
    if (candidates_.empty()) return false;
    if (mode_ == 2 && key == VK_TAB) return Commit(selected_);
    if (mode_ == 2 && (key == VK_SPACE || key == VK_RETURN)) {
      swallow_character_ = key == VK_SPACE ? L' ' : L'\r';
      swallow_next_character_ = true;
      return CommitRaw(key == VK_SPACE ? L' ' : L'\r');
    }
    if (mode_ == 2 && (key == VK_LEFT || key == VK_RIGHT)) {
      selected_ = key == VK_LEFT
          ? (selected_ == 0 ? static_cast<unsigned>(candidates_.size() - 1) : selected_ - 1)
          : (selected_ + 1) % static_cast<unsigned>(candidates_.size());
      RenderCandidates();
      return true;
    }
    if (mode_ != 2 && (key == VK_SPACE || key == VK_RETURN)) {
      if (key == VK_SPACE) {
        swallow_character_ = L' ';
        swallow_next_character_ = true;
      }
      return Commit(selected_);
    }
    if (mode_ != 2 && key >= L'1' && key <= L'5') {
      swallow_character_ = static_cast<wchar_t>(key);
      swallow_next_character_ = true;
      return Commit(static_cast<unsigned>(key - L'1'));
    }
    if (key == VK_DOWN) {
      if (mode_ == 2) return false;
      if (!expanded_ && candidates_.size() > CandidateWindow::kCandidatesPerPage) {
        expanded_ = true;
      } else {
        selected_ = (selected_ + 1) % static_cast<unsigned>(candidates_.size());
      }
      RenderCandidates();
      return true;
    }
    if (key == VK_UP) {
      if (mode_ == 2) return false;
      if (expanded_ && selected_ == 0) {
        expanded_ = false;
      } else {
        selected_ = selected_ == 0 ? static_cast<unsigned>(candidates_.size() - 1) : selected_ - 1;
      }
      RenderCandidates();
      return true;
    }
    return false;
  }

  bool HandleCharacter(wchar_t character) {
    if (swallow_next_character_ &&
        (swallow_character_ == L'\0' || swallow_character_ == character)) {
      swallow_character_ = L'\0';
      swallow_next_character_ = false;
      return true;
    }
    if (mode_ != 2 || candidates_.empty() || !IsEnglishPunctuation(character)) return false;
    return CommitRaw(character);
  }

  bool Choose(unsigned action) {
    if (action < candidates_.size()) return Commit(action);
    return false;
  }

  bool Commit(unsigned index, bool append_space = true) {
    if (index >= candidates_.size()) return false;
    AppendOutput(candidates_[index] + (append_space ? L" " : L""));
    SetWindowTextW(input_, L"");
    candidate_window_.Hide();
    selected_ = 0;
    SetFocus(input_);
    return true;
  }

  bool CommitRaw(wchar_t trailing_character) {
    const std::wstring input = InputText();
    if (input.empty()) return false;
    AppendOutput(input + std::wstring(1, trailing_character));
    SetWindowTextW(input_, L"");
    candidate_window_.Hide();
    selected_ = 0;
    SetFocus(input_);
    return true;
  }

  void AppendOutput(const std::wstring& value) {
    const int end = GetWindowTextLengthW(output_);
    SendMessageW(output_, EM_SETSEL, end, end);
    SendMessageW(output_, EM_REPLACESEL, FALSE, reinterpret_cast<LPARAM>(value.c_str()));
  }

  HWND hwnd_ = nullptr;
  HWND input_ = nullptr;
  HWND output_ = nullptr;
  HWND guidance_ = nullptr;
  HWND english_button_ = nullptr;
  HWND simplified_button_ = nullptr;
  HWND traditional_button_ = nullptr;
  HFONT font_ = nullptr;
  HFONT body_font_ = nullptr;
  int mode_ = 2;
  unsigned selected_ = 0;
  bool expanded_ = false;
  wchar_t swallow_character_ = L'\0';
  bool swallow_next_character_ = false;
  std::wstring preview_local_app_data_;
  std::vector<std::wstring> candidates_;
  std::unique_ptr<PinyinEngine> engine_;
  CandidateWindow candidate_window_;
};

}  // namespace

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE, PWSTR, int show_command) {
  SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
  CandidateLab app;
  return app.Run(instance, show_command);
}
