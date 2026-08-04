#include <windows.h>
#include <msctf.h>

#include <algorithm>
#include <atomic>
#include <memory>
#include <limits>
#include <string>
#include <utility>
#include <vector>

#include "SelectionCallback.h"
#include "CandidateLayout.h"
#include "Guids.h"
#include "HostedPinyinEngine.h"
#include "InputCapturePolicy.h"
#include "InputMode.h"
#include "KeyPolicy.h"
#include "PunctuationPolicy.h"

namespace {
constexpr unsigned kCandidatesPerPage = 5;
constexpr unsigned kToggleModeAction = std::numeric_limits<unsigned>::max();
constexpr unsigned kPreviousPageAction = kToggleModeAction - 1;
constexpr unsigned kNextPageAction = kToggleModeAction - 2;
constexpr unsigned kToggleExpandedAction = kToggleModeAction - 3;
constexpr unsigned kPreviousExpandedPageAction = kToggleModeAction - 4;
constexpr unsigned kNextExpandedPageAction = kToggleModeAction - 5;
constexpr unsigned kExpandedCandidatesPerPage = 5 * 5;
HINSTANCE g_module = nullptr;

std::wstring GuidToString(REFGUID guid) {
  wchar_t value[40]{};
  StringFromGUID2(guid, value, 40);
  return value;
}

std::wstring ModuleDirectory() {
  wchar_t path[MAX_PATH]{};
  GetModuleFileNameW(g_module, path, MAX_PATH);
  std::wstring directory(path);
  const size_t separator = directory.find_last_of(L"\\/");
  return separator == std::wstring::npos ? std::wstring{} : directory.substr(0, separator);
}

HRESULT SetRegString(HKEY key, const wchar_t* name, const std::wstring& value) {
  return RegSetValueExW(key, name, 0, REG_SZ, reinterpret_cast<const BYTE*>(value.c_str()),
                        static_cast<DWORD>((value.size() + 1) * sizeof(wchar_t))) == ERROR_SUCCESS ? S_OK : E_FAIL;
}

#ifdef GY_IME_TRACE
void TraceRect(const wchar_t* event, const RECT& rect) {
  wchar_t directory[MAX_PATH]{};
  if (!GetTempPathW(MAX_PATH, directory)) return;
  const std::wstring path = std::wstring(directory) + L"GyIme.trace.log";
  const HANDLE file = CreateFileW(path.c_str(), FILE_APPEND_DATA, FILE_SHARE_READ | FILE_SHARE_WRITE,
                                  nullptr, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) return;
  wchar_t line[256]{};
  const int length = swprintf_s(line, L"pid=%lu event=%ls rect=%ld,%ld,%ld,%ld\r\n",
                                GetCurrentProcessId(), event, rect.left, rect.top, rect.right, rect.bottom);
  DWORD written = 0;
  if (length > 0) WriteFile(file, line, static_cast<DWORD>(length * sizeof(wchar_t)), &written, nullptr);
  CloseHandle(file);
}
void Trace(const wchar_t* event, HRESULT hr = S_OK, WPARAM key = 0) {
  wchar_t directory[MAX_PATH]{};
  if (!GetTempPathW(MAX_PATH, directory)) return;
  const std::wstring path = std::wstring(directory) + L"GyIme.trace.log";
  const HANDLE file = CreateFileW(path.c_str(), FILE_APPEND_DATA, FILE_SHARE_READ | FILE_SHARE_WRITE,
                                  nullptr, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) return;
  wchar_t line[256]{};
  const int length = swprintf_s(line, L"pid=%lu event=%ls hr=0x%08lX key=%llu\r\n",
                                GetCurrentProcessId(), event, static_cast<unsigned long>(hr),
                                static_cast<unsigned long long>(key));
  DWORD written = 0;
  if (length > 0) WriteFile(file, line, static_cast<DWORD>(length * sizeof(wchar_t)), &written, nullptr);
  CloseHandle(file);
}
#else
void Trace(const wchar_t*, HRESULT = S_OK, WPARAM = 0) {}
void TraceRect(const wchar_t*, const RECT&) {}
#endif

enum class EditActionKind { Append, InsertText, Backspace, CommitCandidate, CommitRaw, Cancel };
struct EditAction {
  EditActionKind kind;
  wchar_t character = 0;
  unsigned index = 0;
  unsigned long long mode_generation = 0;
};

class GyTextService;
class EditSession final : public ITfEditSession {
public:
  EditSession(GyTextService* owner, ITfContext* context, EditAction action)
      : owner_(owner), context_(context), action_(action) {
    if (context_) context_->AddRef();
  }
  ~EditSession() { if (context_) context_->Release(); }
  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid, void** object) override;
  ULONG STDMETHODCALLTYPE AddRef() override { return ++refs_; }
  ULONG STDMETHODCALLTYPE Release() override { const ULONG refs = --refs_; if (!refs) delete this; return refs; }
  HRESULT STDMETHODCALLTYPE DoEditSession(TfEditCookie cookie) override;
private:
  std::atomic<ULONG> refs_{1};
  GyTextService* owner_;
  ITfContext* context_;
  EditAction action_;
};

class GyTextService final : public ITfTextInputProcessorEx, public ITfKeyEventSink, public ITfThreadMgrEventSink, public ITfCompositionSink {
public:
  GyTextService() : engine_(ModuleDirectory()), selection_callback_(g_module, [this](unsigned action) { return HandleHostAction(action); }) {}
  ~GyTextService() { Deactivate(); }
  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid, void** object) override {
    if (!object) return E_INVALIDARG; *object = nullptr;
    if (iid == IID_IUnknown || iid == IID_ITfTextInputProcessor || iid == IID_ITfTextInputProcessorEx) *object = static_cast<ITfTextInputProcessorEx*>(this);
    else if (iid == IID_ITfKeyEventSink) *object = static_cast<ITfKeyEventSink*>(this);
    else if (iid == IID_ITfThreadMgrEventSink) *object = static_cast<ITfThreadMgrEventSink*>(this);
    else if (iid == IID_ITfCompositionSink) *object = static_cast<ITfCompositionSink*>(this);
    else return E_NOINTERFACE;
    AddRef(); return S_OK;
  }
  ULONG STDMETHODCALLTYPE AddRef() override { return ++refs_; }
  ULONG STDMETHODCALLTYPE Release() override { const ULONG refs = --refs_; if (!refs) delete this; return refs; }
  HRESULT STDMETHODCALLTYPE Activate(ITfThreadMgr* manager, TfClientId client) override { return ActivateEx(manager, client, 0); }
  HRESULT STDMETHODCALLTYPE ActivateEx(ITfThreadMgr* manager, TfClientId client, DWORD) override {
    Trace(L"activate.begin");
    if (!manager) return E_INVALIDARG;
    Deactivate();
    thread_mgr_ = manager;
    thread_mgr_->AddRef();
    client_id_ = client;
    HRESULT hr = thread_mgr_->QueryInterface(IID_ITfKeystrokeMgr, reinterpret_cast<void**>(&keystroke_mgr_));
    Trace(L"activate.keystroke-manager", hr);
    if (FAILED(hr)) return hr;
    hr = keystroke_mgr_->AdviseKeyEventSink(client_id_, static_cast<ITfKeyEventSink*>(this), TRUE);
    Trace(L"activate.advise-key-sink", hr);
    if (FAILED(hr)) return hr;
    ITfSource* source = nullptr;
    if (SUCCEEDED(thread_mgr_->QueryInterface(IID_ITfSource, reinterpret_cast<void**>(&source)))) {
      const HRESULT sink_hr = source->AdviseSink(IID_ITfThreadMgrEventSink,
          static_cast<ITfThreadMgrEventSink*>(this), &thread_mgr_sink_);
      Trace(L"activate.advise-focus-sink", sink_hr);
      source->Release();
    }
    if (!selection_callback_.Start()) {
      Trace(L"activate.selection-callback", E_FAIL);
      Deactivate();
      return E_FAIL;
    }
    // Non-blocking startup moves the cold Host launch off the first keystroke.
    engine_.Prewarm();
    SynchronizeInputMode(false);
    return S_OK;
  }  HRESULT STDMETHODCALLTYPE Deactivate() override {
    selection_callback_.Stop();
    CancelComposition();
    if (keystroke_mgr_) { keystroke_mgr_->UnadviseKeyEventSink(client_id_); keystroke_mgr_->Release(); keystroke_mgr_ = nullptr; }
    if (thread_mgr_ && thread_mgr_sink_ != TF_INVALID_COOKIE) { ITfSource* source = nullptr; if (SUCCEEDED(thread_mgr_->QueryInterface(IID_ITfSource, reinterpret_cast<void**>(&source)))) { source->UnadviseSink(thread_mgr_sink_); source->Release(); } }
    thread_mgr_sink_ = TF_INVALID_COOKIE;
    if (context_) { context_->Release(); context_ = nullptr; last_caret_valid_ = false; }
    if (thread_mgr_) { thread_mgr_->Release(); thread_mgr_ = nullptr; }
    shift_down_ = shift_used_ = false;
    // The selected language survives profile reactivation so it never changes
    // by surprise between 简体、繁体 and EN.
    control_down_ = alt_down_ = win_down_ = false;
    client_id_ = TF_CLIENTID_NULL; return S_OK;
  }

  HRESULT STDMETHODCALLTYPE OnSetFocus(BOOL focused) override {
    Trace(L"focus.app", S_OK, focused ? 1 : 0);
    // Browser address bars, developer tools and cross-page navigation can move
    // focus before Windows delivers the final Ctrl/Alt/Win key-up. Never carry
    // that stale modifier state into the next editable control, otherwise
    // ShouldEat() treats ordinary letters as application shortcuts.
    ResetTransientKeyboardState();
    if (!focused) CancelComposition();
    else SynchronizeInputMode(false);
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE OnTestKeyDown(ITfContext*, WPARAM key, LPARAM, BOOL* eaten) override {
    ReconcileModifierState();
    if (!eaten) return E_INVALIDARG;
    if (gy::keys::ShouldMarkShiftUsed(shift_down_, key)) shift_used_ = true;
    SynchronizeInputMode(false);
    *eaten = IsShiftKey(key) ? gy::keys::ShouldCaptureShift(HasShortcutModifier()) : ShouldEat(key);
    if (key >= 'A' && key <= 'Z') Trace(L"key.test", S_OK, key);
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE OnTestKeyUp(ITfContext*, WPARAM key, LPARAM, BOOL* eaten) override {
    if (!eaten) return E_INVALIDARG;
    // A focus switch can leave a cached Ctrl/Alt/Win state behind. Reconcile
    // before deciding whether a plain Shift release is the GY mode toggle.
    ReconcileModifierState();
    *eaten = IsShiftKey(key) && gy::keys::ShouldCaptureShift(HasShortcutModifier());
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE OnKeyDown(ITfContext* context, WPARAM key, LPARAM, BOOL* eaten) override {
    if (!eaten) return E_INVALIDARG;
    *eaten = FALSE;
    if (IsShiftKey(key)) { shift_down_ = true; shift_used_ = HasShortcutModifier(); return S_OK; }
    if (shift_down_) shift_used_ = true;
    UpdateModifierState(key, true);
    ReconcileModifierState();
    SynchronizeInputMode(false);
    Trace(L"key.down", S_OK, key);

    // Shift alone changes the GY conversion mode. Ctrl+Space and other
    // application shortcuts are deliberately passed through untouched.
    if (!ShouldEat(key)) return S_OK;
    SetContext(context);
    *eaten = TRUE;
    if (const wchar_t punctuation = ChinesePunctuation(key); punctuation != 0) {
      Trace(L"key.punctuation", S_OK, key);
      return RequestEdit({EditActionKind::InsertText, punctuation});
    }
    if (key >= 'A' && key <= 'Z') return RequestEdit({EditActionKind::Append, static_cast<wchar_t>(key - 'A' + L'a')});
    if (key == VK_OEM_7) return RequestEdit({EditActionKind::Append, L'\''});
    if (key == VK_BACK) return RequestEdit({EditActionKind::Backspace});
    if (key == VK_ESCAPE) return RequestEdit({EditActionKind::Cancel});
    // In the compact strip Enter preserves the established raw-pinyin path.
    // Once the user explicitly opens the 5 x 5 grid, Enter and Space both
    // commit the currently highlighted candidate.
    if (gy::keys::ShouldCommitSelectedCandidate(key, expanded_candidates_)) {
      return RequestEdit({EditActionKind::CommitCandidate, 0, selected_});
    }
    if (gy::keys::IsRawTextCommitKey(key)) return RequestEdit({EditActionKind::CommitRaw});
    if (key >= '1' && key <= '5') {
      unsigned candidate_index = page_start_ + static_cast<unsigned>(key - '1');
      if (expanded_candidates_) {
        candidate_index = gy::candidate_layout::ExpandedDigitCandidate(
            selected_, page_start_, static_cast<unsigned>(candidates_.size()),
            static_cast<unsigned>(key - '0'));
      }
      // The short final row has no hidden candidate behind a missing column.
      // Keep the digit consumed while composition is active, but never commit
      // a different item than the user asked for.
      if (candidate_index >= candidates_.size()) return S_OK;
      return RequestEdit({EditActionKind::CommitCandidate, 0, candidate_index});
    }
    if (key == VK_PRIOR) { MovePage(-1, PageSizeForCurrentView()); ShowCandidates(context_, nullptr); return S_OK; }
    if (key == VK_UP) {
      if (expanded_candidates_) {
        // The first ↑ on page one is the deliberate exit gesture. On later
        // pages, ↑ continues to the prior 5 × 5 page in the same column.
        if (page_start_ == 0 && selected_ < kCandidatesPerPage) {
          expanded_candidates_ = false;
          page_start_ = selected_ / kCandidatesPerPage * kCandidatesPerPage;
        } else {
          selected_ = gy::candidate_layout::MoveExpandedUp(
              selected_, page_start_, static_cast<unsigned>(candidates_.size()));
          page_start_ = selected_ / kExpandedCandidatesPerPage * kExpandedCandidatesPerPage;
        }
      } else {
        MovePage(-1, kCandidatesPerPage);
      }
      ShowCandidates(context_, nullptr);
      return S_OK;
    }
    if (key == VK_NEXT) { MovePage(1, PageSizeForCurrentView()); ShowCandidates(context_, nullptr); return S_OK; }
    if (key == VK_DOWN) {
      if (!expanded_candidates_) {
        expanded_candidates_ = true;
        page_start_ = selected_ / kExpandedCandidatesPerPage * kExpandedCandidatesPerPage;
      } else {
        selected_ = gy::candidate_layout::MoveExpandedDown(
            selected_, page_start_, static_cast<unsigned>(candidates_.size()));
        page_start_ = selected_ / kExpandedCandidatesPerPage * kExpandedCandidatesPerPage;
      }
      ShowCandidates(context_, nullptr);
      return S_OK;
    }
    if (key == VK_LEFT) {
      if (expanded_candidates_) {
        selected_ = gy::candidate_layout::MoveExpandedLeft(
            selected_, page_start_, static_cast<unsigned>(candidates_.size()));
      } else {
        MoveSelection(-1);
      }
      ShowCandidates(context_, nullptr);
      return S_OK;
    }
    if (key == VK_RIGHT) {
      if (expanded_candidates_) {
        selected_ = gy::candidate_layout::MoveExpandedRight(
            selected_, page_start_, static_cast<unsigned>(candidates_.size()));
      } else {
        MoveSelection(1);
      }
      ShowCandidates(context_, nullptr);
      return S_OK;
    }
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE OnKeyUp(ITfContext*, WPARAM key, LPARAM, BOOL* eaten) override {
    if (!eaten) return E_INVALIDARG;
    *eaten = FALSE;
    // Use real keyboard state so a return from another app cannot suppress a
    // bare-Shift Chinese/English toggle.
    ReconcileModifierState();
    SynchronizeInputMode(false);
    const bool should_toggle = IsShiftKey(key) && gy::keys::ShouldToggleMode(shift_down_, shift_used_, HasShortcutModifier());
    if (IsShiftKey(key)) shift_down_ = false;
    UpdateModifierState(key, false);
    if (should_toggle) { ToggleEnglishMode(); *eaten = TRUE; }
    return S_OK;
  }  HRESULT STDMETHODCALLTYPE OnPreservedKey(ITfContext*, REFGUID, BOOL* eaten) override { if (!eaten) return E_INVALIDARG; *eaten = FALSE; return S_OK; }
  HRESULT STDMETHODCALLTYPE OnCompositionTerminated(TfEditCookie, ITfComposition* composition) override {
    Trace(L"composition.terminated");
    if (composition && composition == composition_) ResetCompositionState();
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE OnInitDocumentMgr(ITfDocumentMgr*) override { return S_OK; }
  HRESULT STDMETHODCALLTYPE OnUninitDocumentMgr(ITfDocumentMgr*) override { return S_OK; }
  HRESULT STDMETHODCALLTYPE OnSetFocus(ITfDocumentMgr*, ITfDocumentMgr* focus) override {
    Trace(L"focus.document", S_OK, focus ? 1 : 0);
    CancelComposition();
    ResetTransientKeyboardState();
    if (!focus) { SetContext(nullptr); return S_OK; }
    ITfContext* context = nullptr;
    if (SUCCEEDED(focus->GetTop(&context))) SetContext(context);
    if (context) context->Release();
    // The mode is persisted by Settings / Shift. Re-read it after every
    // document focus change so a tab with a stale TSF instance cannot leave
    // the newly focused field in EN while the user has selected Chinese.
    SynchronizeInputMode(false);
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE OnPushContext(ITfContext*) override { return S_OK; }
  HRESULT STDMETHODCALLTYPE OnPopContext(ITfContext*) override { return S_OK; }
  HRESULT ApplyEdit(ITfContext* edit_context, const EditAction& action, TfEditCookie cookie) {
    // A request posted by a window that has already lost focus must not edit the new window.
    if (!edit_context || edit_context != context_) return S_OK;
    // Once a mode transition happened, old Chinese edit work is stale. This is
    // the final EN direct-mode guard against queued TSF edit sessions.
    if (action.mode_generation != mode_generation_) return S_OK;
    if (gy::input_mode::IsEnglish(input_mode_) && action.kind != EditActionKind::Cancel) return S_OK;
    if (action.kind == EditActionKind::InsertText) {
      HRESULT hr = S_OK;
      if (composition_) hr = CommitComposition(edit_context, cookie, selected_);
      return FAILED(hr) ? hr : InsertText(edit_context, cookie, action.character);
    }
    if (action.kind == EditActionKind::Append) {
      composition_text_ += action.character;
      candidates_ = engine_.Lookup(composition_text_);
      selected_ = 0;
      page_start_ = 0;
      expanded_candidates_ = false;
      return UpdateComposition(edit_context, cookie);
    }
    if (action.kind == EditActionKind::Backspace) {
      if (!composition_text_.empty()) composition_text_.pop_back();
      candidates_ = engine_.Lookup(composition_text_);
      selected_ = 0;
      page_start_ = 0;
      expanded_candidates_ = false;
      return composition_text_.empty() ? ClearComposition(cookie) : UpdateComposition(edit_context, cookie);
    }
    if (action.kind == EditActionKind::CommitCandidate) return CommitComposition(edit_context, cookie, action.index);
    if (action.kind == EditActionKind::CommitRaw) return CommitComposition(edit_context, cookie, 0, true);
    return ClearComposition(cookie);
  }
private:
  static bool IsDown(int virtual_key) { return (GetKeyState(virtual_key) & 0x8000) != 0; }
  static bool IsPhysicallyDown(int virtual_key) { return (GetAsyncKeyState(virtual_key) & 0x8000) != 0; }
  void UpdateModifierState(WPARAM key, bool down) {
    switch (key) {
      case VK_CONTROL: case VK_LCONTROL: case VK_RCONTROL: control_down_ = down; break;
      case VK_MENU: case VK_LMENU: case VK_RMENU: alt_down_ = down; break;
      case VK_LWIN: case VK_RWIN: win_down_ = down; break;
      default: break;
    }
  }
  void ResetTransientKeyboardState() {
    shift_down_ = false;
    shift_used_ = false;
    control_down_ = false;
    alt_down_ = false;
    win_down_ = false;
  }
  void ReconcileModifierState() {
    // Alt+Tab and browser renderer switches can route the final modifier key-up
    // to another process. A stale cached Alt/Ctrl/Win must never make GY treat
    // normal letters as application shortcuts after focus returns.
    const auto physically_down = [](int key) {
      return IsDown(key) || IsPhysicallyDown(key);
    };
    if (!physically_down(VK_CONTROL) && !physically_down(VK_LCONTROL) && !physically_down(VK_RCONTROL)) control_down_ = false;
    if (!physically_down(VK_MENU) && !physically_down(VK_LMENU) && !physically_down(VK_RMENU)) alt_down_ = false;
    if (!physically_down(VK_LWIN) && !physically_down(VK_RWIN)) win_down_ = false;
  }
  static bool IsShiftKey(WPARAM key) { return gy::keys::IsShiftKey(key); }
  bool IsControlDown() const {
    return control_down_ || IsDown(VK_CONTROL) || IsDown(VK_LCONTROL) || IsDown(VK_RCONTROL) ||
        IsPhysicallyDown(VK_CONTROL) || IsPhysicallyDown(VK_LCONTROL) || IsPhysicallyDown(VK_RCONTROL);
  }
  bool HasShortcutModifier() const {
    return IsControlDown() || alt_down_ || win_down_ || IsDown(VK_MENU) || IsDown(VK_LWIN) || IsDown(VK_RWIN) ||
        IsPhysicallyDown(VK_MENU) || IsPhysicallyDown(VK_LWIN) || IsPhysicallyDown(VK_RWIN);
  }  unsigned CurrentPageCandidateCount() const {
    if (page_start_ >= candidates_.size()) return 0;
    return std::min<unsigned>(kCandidatesPerPage,
                              static_cast<unsigned>(candidates_.size()) - page_start_);
  }
  unsigned PageSizeForCurrentView() const { return expanded_candidates_ ? kExpandedCandidatesPerPage : kCandidatesPerPage; }
  void MoveSelection(int delta) {
    if (candidates_.empty()) return;
    const int count = static_cast<int>(candidates_.size());
    selected_ = static_cast<unsigned>((static_cast<int>(selected_) + delta + count) % count);
    const unsigned page_size = PageSizeForCurrentView();
    page_start_ = selected_ / page_size * page_size;
  }
  void MovePage(int delta, unsigned page_size) {
    if (candidates_.empty()) return;
    page_size = std::max(1u, page_size);
    const int last_page = static_cast<int>((candidates_.size() - 1) / page_size);
    const int current_page = static_cast<int>(page_start_ / page_size);
    const int target_page = std::clamp(current_page + delta, 0, last_page);
    page_start_ = static_cast<unsigned>(target_page) * page_size;
    selected_ = page_start_;
  }
  void ToggleEnglishMode() {
    const int next_mode = gy::input_mode::IsEnglish(input_mode_) ? chinese_mode_ : gy::input_mode::kEnglish;
    gy::input_mode::Write(next_mode);
    ApplyInputMode(next_mode, true);
  }
  void ApplyInputMode(int mode, bool announce) {
    mode = gy::input_mode::Normalize(mode);
    const bool next_english = gy::input_mode::IsEnglish(mode);
    if (mode == input_mode_ && english_mode_ == next_english) return;
    ++mode_generation_;
    if (!composition_text_.empty()) CancelComposition();
    input_mode_ = mode;
    if (!next_english) chinese_mode_ = mode;
    english_mode_ = next_english;
    if (next_english) engine_.HideCandidates();
    if (announce) engine_.ShowMode(last_caret_, input_mode_);
  }
  void SynchronizeInputMode(bool announce) { ApplyInputMode(gy::input_mode::Read(), announce); }
  bool HandleHostAction(unsigned action) {
    if (action == kToggleModeAction) {
      ToggleEnglishMode();
    } else if (action == kToggleExpandedAction) {
      expanded_candidates_ = !expanded_candidates_;
      ShowCandidates(context_, nullptr);
    } else if (action == kPreviousPageAction) {
      MovePage(-1, kCandidatesPerPage);
      ShowCandidates(context_, nullptr);
    } else if (action == kNextPageAction) {
      MovePage(1, kCandidatesPerPage);
      ShowCandidates(context_, nullptr);
    } else if (action == kPreviousExpandedPageAction) {
      MovePage(-1, kExpandedCandidatesPerPage);
      ShowCandidates(context_, nullptr);
    } else if (action == kNextExpandedPageAction) {
      MovePage(1, kExpandedCandidatesPerPage);
      ShowCandidates(context_, nullptr);
    } else {
      return Select(action);
    }
    return true;
  }
  wchar_t ChinesePunctuation(WPARAM key) {
    if (gy::input_mode::IsEnglish(input_mode_) || HasShortcutModifier()) return 0;
    const bool shift = IsDown(VK_SHIFT) || shift_down_;
    if (gy::punctuation::IsQuoteKey(key)) {
      const bool double_quote = shift;
      bool& opening = double_quote ? double_quote_open_ : single_quote_open_;
      const wchar_t value = gy::punctuation::QuoteCharacter(double_quote, opening);
      opening = !opening;
      return value;
    }
    return gy::punctuation::ChineseCharacter(key, shift);
  }
  bool ShouldEat(WPARAM key) const {
    return gy::input_capture::ShouldCapture(
        gy::input_mode::IsEnglish(input_mode_), HasShortcutModifier(),
        IsDown(VK_SHIFT) || shift_down_, !composition_text_.empty(),
        CurrentPageCandidateCount(), key);
  }
  void SetContext(ITfContext* context) {
    if (context == context_) return;
    Trace(L"context.change", S_OK, context ? 1 : 0);
    // The remembered caret belongs to the previous context: an app or document
    // switch must never anchor the candidate window to a position measured
    // somewhere else (it jumped across the screen after an app switch).
    last_caret_valid_ = false;
    CancelComposition();
    if (context_) context_->Release();
    context_ = context;
    if (context_) context_->AddRef();
  }
  HRESULT RequestEdit(EditAction action) { if (!context_) { Trace(L"edit.no-context", E_FAIL); return E_FAIL; } action.mode_generation = mode_generation_; auto* edit = new EditSession(this, context_, action); HRESULT session_hr = E_FAIL; const HRESULT hr = context_->RequestEditSession(client_id_, edit, TF_ES_ASYNCDONTCARE | TF_ES_READWRITE, &session_hr); Trace(L"edit.request", FAILED(hr) ? hr : session_hr); edit->Release(); return FAILED(hr) ? hr : session_hr; }
  HRESULT UpdateComposition(ITfContext* edit_context, TfEditCookie cookie) {
    if (!edit_context) return E_FAIL;
    if (!composition_) {
      TF_SELECTION selection{};
      ULONG fetched = 0;
      HRESULT hr = edit_context->GetSelection(cookie, TF_DEFAULT_SELECTION, 1, &selection, &fetched);
      Trace(L"composition.get-selection", hr);
      if (FAILED(hr) || fetched != 1) return FAILED(hr) ? hr : E_FAIL;

      ITfRange* composition_range = nullptr;
      hr = selection.range->Clone(&composition_range);
      Trace(L"composition.clone-selection", hr);
      if (SUCCEEDED(hr)) hr = composition_range->Collapse(cookie, TF_ANCHOR_END);
      Trace(L"composition.collapse", hr);

      ITfContextComposition* composer = nullptr;
      if (SUCCEEDED(hr)) hr = edit_context->QueryInterface(IID_ITfContextComposition, reinterpret_cast<void**>(&composer));
      Trace(L"composition.get-manager", hr);
      if (SUCCEEDED(hr)) {
        hr = composer->StartComposition(cookie, composition_range,
                                        static_cast<ITfCompositionSink*>(this), &composition_);
      }
      Trace(L"composition.start", hr);
      if (composer) composer->Release();
      if (composition_range) composition_range->Release();
      selection.range->Release();
      if (FAILED(hr)) return hr;
      if (!composition_) { Trace(L"composition.rejected", E_FAIL); return E_FAIL; }
    }
    ITfRange* range = nullptr;
    HRESULT hr = composition_->GetRange(&range);
    Trace(L"composition.get-range", hr);
    if (SUCCEEDED(hr)) {
      hr = range->SetText(cookie, 0, composition_text_.c_str(), static_cast<LONG>(composition_text_.size()));
      Trace(L"composition.set-text", hr);
      if (SUCCEEDED(hr)) {
        // Measure the candidate anchor on the full composition range first,
        // then pin the caret to the composition end: XAML hosts (Win11
        // Notepad) leave the caret at the composition start after SetText.
        ShowCandidates(edit_context, range, cookie);
        range->Collapse(cookie, TF_ANCHOR_END);
        TF_SELECTION selection{};
        selection.range = range;
        selection.style.ase = TF_AE_NONE;
        selection.style.fInterimChar = FALSE;
        Trace(L"composition.selection", edit_context->SetSelection(cookie, 1, &selection));
      }
      range->Release();
    }
    return hr;
  }
  HRESULT InsertText(ITfContext* edit_context, TfEditCookie cookie, wchar_t character) {
    if (!edit_context || character == 0) return E_INVALIDARG;
    TF_SELECTION selection{};
    ULONG fetched = 0;
    HRESULT hr = edit_context->GetSelection(cookie, TF_DEFAULT_SELECTION, 1, &selection, &fetched);
    if (FAILED(hr) || fetched != 1 || !selection.range) return FAILED(hr) ? hr : E_FAIL;
    hr = selection.range->SetText(cookie, 0, &character, 1);
    if (SUCCEEDED(hr)) {
      selection.range->Collapse(cookie, TF_ANCHOR_END);
      hr = edit_context->SetSelection(cookie, 1, &selection);
    }
    selection.range->Release();
    return hr;
  }
  HRESULT CommitComposition(ITfContext* edit_context, TfEditCookie cookie, unsigned index, bool raw_text = false) {
    if (!composition_) return S_OK;
    const bool selected_candidate = !raw_text && index < candidates_.size();
    const std::wstring pinyin = composition_text_;
    const std::wstring text = selected_candidate ? candidates_[index] : composition_text_;
    ITfRange* range = nullptr;
    HRESULT hr = composition_->GetRange(&range);
    if (SUCCEEDED(hr)) {
      hr = range->SetText(cookie, 0, text.c_str(), static_cast<LONG>(text.size()));
    }
    if (SUCCEEDED(hr)) hr = composition_->EndComposition(cookie);
    // XAML hosts (Win11 Notepad) restore the selection to the composition start
    // on EndComposition; the next commit then inserts before the previous one
    // and text accumulates backwards. Pin the caret to the end of the commit.
    if (SUCCEEDED(hr) && range && edit_context) {
      range->Collapse(cookie, TF_ANCHOR_END);
      TF_SELECTION selection{};
      selection.range = range;
      selection.style.ase = TF_AE_NONE;
      selection.style.fInterimChar = FALSE;
      Trace(L"commit.selection", edit_context->SetSelection(cookie, 1, &selection));
    }
    if (range) range->Release();
    composition_->Release();
    composition_ = nullptr;
    if (SUCCEEDED(hr) && selected_candidate) engine_.Learn(pinyin, text);
    composition_text_.clear();
    candidates_.clear();
    selected_ = 0;
    page_start_ = 0;
    expanded_candidates_ = false;
    engine_.HideCandidates();
    return hr;
  }
  HRESULT ClearComposition(TfEditCookie cookie) {
    if (!composition_) { ResetCompositionState(); return S_OK; }
    ITfRange* range = nullptr;
    HRESULT hr = composition_->GetRange(&range);
    if (SUCCEEDED(hr)) {
      hr = range->SetText(cookie, 0, L"", 0);
      range->Release();
    }
    const HRESULT end_hr = composition_->EndComposition(cookie);
    ResetCompositionState();
    return FAILED(hr) ? hr : end_hr;
  }
  void ResetCompositionState() {
    if (composition_) { composition_->Release(); composition_ = nullptr; }
    composition_text_.clear();
    candidates_.clear();
    selected_ = 0;
    page_start_ = 0;
    engine_.HideCandidates();
    expanded_candidates_ = false;
  }
  void CancelComposition() {
    if (composition_ && context_ && client_id_ != TF_CLIENTID_NULL) {
      const HRESULT hr = RequestEdit({EditActionKind::Cancel});
      if (hr == S_OK) return;
    }
    ResetCompositionState();
  }
  void ShowCandidates(ITfContext* edit_context, ITfRange* known_range, TfEditCookie cookie = TF_INVALID_EDIT_COOKIE) {
    if (gy::input_mode::IsEnglish(input_mode_) || candidates_.empty()) { engine_.HideCandidates(); return; }
    RECT caret = last_caret_;
    bool have_caret = last_caret_valid_;
    ITfRange* range = known_range;
    bool release_range = false;
    if (!range && composition_ && SUCCEEDED(composition_->GetRange(&range))) release_range = range != nullptr;
    if (range && edit_context && cookie != TF_INVALID_EDIT_COOKIE) {
      ITfContextView* view = nullptr;
      BOOL clipped = FALSE;
      if (SUCCEEDED(edit_context->GetActiveView(&view))) {
        RECT measured{};
        // A clipped rect still belongs to this context; a caret remembered
        // from another app does not. ShowInternal clamps the window on-screen.
        if (SUCCEEDED(view->GetTextExt(cookie, range, &measured, &clipped))) {
          caret = measured;
          last_caret_ = measured;
          last_caret_valid_ = true;
          have_caret = true;
          TraceRect(L"caret.tsf", measured);
        }
        view->Release();
      }
    }
    if (release_range) range->Release();
    {  // A clearly disagreeing system caret vetoes the TSF rect: Win11 Notepad's XAML view reports GetTextExt shifted by its tab strip.
      // A caret remembered from another context is never used:
      // last_caret_valid_ keeps cross-context anchors out. The key handler
      // runs on the target thread, so this thread's GUI caret belongs here.
      GUITHREADINFO gui{sizeof(gui)};
      if (GetGUIThreadInfo(GetCurrentThreadId(), &gui) && gui.hwndCaret &&
          (gui.rcCaret.right > gui.rcCaret.left || gui.rcCaret.bottom > gui.rcCaret.top)) {
        POINT origin{gui.rcCaret.left, gui.rcCaret.top};
        if (ClientToScreen(gui.hwndCaret, &origin)) {
          const RECT gui_caret{origin.x, origin.y, origin.x + (gui.rcCaret.right - gui.rcCaret.left),
                               origin.y + (gui.rcCaret.bottom - gui.rcCaret.top)};
          const LONG veto = ((caret.bottom - caret.top) > (gui_caret.bottom - gui_caret.top) ? (caret.bottom - caret.top) : (gui_caret.bottom - gui_caret.top)) / 2 + 8;
          if (!have_caret || (caret.top + caret.bottom) - (gui_caret.top + gui_caret.bottom) > 2 * veto || (gui_caret.top + gui_caret.bottom) - (caret.top + caret.bottom) > 2 * veto) { caret = gui_caret; last_caret_ = gui_caret; last_caret_valid_ = true; have_caret = true; TraceRect(L"caret.gui", gui_caret); }
        }
      }
    }
    if (!have_caret && !last_caret_valid_) {
      // Nothing was ever measured in this context (Chromium's layout can lag
      // one keystroke right after an app switch). One late frame is harmless;
      // a window shown at a stale rect is the drift users actually see.
      TraceRect(L"caret.skip", caret);
      return;
    }
    TraceRect(L"caret.pick", caret);
    engine_.ShowCandidates(caret, candidates_, selected_, page_start_, input_mode_, expanded_candidates_, selection_callback_.Endpoint());
  }
  bool Select(unsigned index) { if (index >= candidates_.size()) return false; return SUCCEEDED(RequestEdit({EditActionKind::CommitCandidate, 0, index})); }
  std::atomic<ULONG> refs_{1}; ITfThreadMgr* thread_mgr_ = nullptr; ITfKeystrokeMgr* keystroke_mgr_ = nullptr; ITfContext* context_ = nullptr; ITfComposition* composition_ = nullptr; TfClientId client_id_ = TF_CLIENTID_NULL; DWORD thread_mgr_sink_ = TF_INVALID_COOKIE; HostedPinyinEngine engine_; SelectionCallback selection_callback_; RECT last_caret_{0, 0, 360, 24}; bool last_caret_valid_ = false; std::wstring composition_text_; std::vector<std::wstring> candidates_; unsigned selected_ = 0; unsigned page_start_ = 0; bool expanded_candidates_ = false; int input_mode_ = gy::input_mode::kSimplified; int chinese_mode_ = gy::input_mode::kSimplified; bool english_mode_ = false; unsigned long long mode_generation_ = 0; bool single_quote_open_ = true; bool double_quote_open_ = true; bool shift_down_ = false; bool shift_used_ = false; bool control_down_ = false; bool alt_down_ = false; bool win_down_ = false;
  friend class EditSession;
};

HRESULT EditSession::QueryInterface(REFIID iid, void** object) { if (!object) return E_INVALIDARG; *object = nullptr; if (iid == IID_IUnknown || iid == IID_ITfEditSession) { *object = static_cast<ITfEditSession*>(this); AddRef(); return S_OK; } return E_NOINTERFACE; }
HRESULT EditSession::DoEditSession(TfEditCookie cookie) { return owner_->ApplyEdit(context_, action_, cookie); }
class ClassFactory final : public IClassFactory {
public:
  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid, void** object) override { if (!object) return E_INVALIDARG; *object = nullptr; if (iid == IID_IUnknown || iid == IID_IClassFactory) { *object = static_cast<IClassFactory*>(this); AddRef(); return S_OK; } return E_NOINTERFACE; }
  ULONG STDMETHODCALLTYPE AddRef() override { return ++refs_; } ULONG STDMETHODCALLTYPE Release() override { const ULONG refs = --refs_; if (!refs) delete this; return refs; }
  HRESULT STDMETHODCALLTYPE CreateInstance(IUnknown* outer, REFIID iid, void** object) override { if (outer) return CLASS_E_NOAGGREGATION; auto* service = new GyTextService(); const HRESULT hr = service->QueryInterface(iid, object); service->Release(); return hr; }
  HRESULT STDMETHODCALLTYPE LockServer(BOOL) override { return S_OK; }
private: std::atomic<ULONG> refs_{1};
};
HRESULT RegisterComServer(bool remove) {
  const std::wstring key_name = L"Software\\Classes\\CLSID\\" + GuidToString(CLSID_GyTextService);
  if (remove) { const LSTATUS result = RegDeleteTreeW(HKEY_LOCAL_MACHINE, key_name.c_str()); return result == ERROR_SUCCESS || result == ERROR_FILE_NOT_FOUND ? S_OK : E_FAIL; }
  HKEY key = nullptr; if (RegCreateKeyExW(HKEY_LOCAL_MACHINE, key_name.c_str(), 0, nullptr, 0, KEY_WRITE, nullptr, &key, nullptr) != ERROR_SUCCESS) return E_FAIL; const HRESULT title_hr = SetRegString(key, nullptr, L"GY 输入法文本服务"); RegCloseKey(key); if (FAILED(title_hr)) return title_hr;
  HKEY server = nullptr; if (RegCreateKeyExW(HKEY_LOCAL_MACHINE, (key_name + L"\\InprocServer32").c_str(), 0, nullptr, 0, KEY_WRITE, nullptr, &server, nullptr) != ERROR_SUCCESS) return E_FAIL; wchar_t path[MAX_PATH]{}; GetModuleFileNameW(g_module, path, MAX_PATH); const HRESULT path_hr = SetRegString(server, nullptr, path); const HRESULT model_hr = SetRegString(server, L"ThreadingModel", L"Apartment"); RegCloseKey(server); return FAILED(path_hr) ? path_hr : model_hr;
}
HRESULT RegisterProfile(bool remove) {
  constexpr LANGID kChinese = MAKELANGID(LANG_CHINESE, SUBLANG_CHINESE_SIMPLIFIED);
  ITfInputProcessorProfileMgr* profiles = nullptr;
  HRESULT hr = CoCreateInstance(CLSID_TF_InputProcessorProfiles, nullptr, CLSCTX_INPROC_SERVER,
                                IID_ITfInputProcessorProfileMgr, reinterpret_cast<void**>(&profiles));
  if (FAILED(hr)) return hr;
  if (remove) {
    hr = profiles->UnregisterProfile(CLSID_GyTextService, kChinese, GUID_PROFILE_GY_PINYIN,
                                     TF_URP_ALLPROFILES);
    if (hr == E_INVALIDARG) hr = S_OK;
  } else {
    // Refresh profile metadata so Windows drops any previously cached default icon.
    profiles->UnregisterProfile(CLSID_GyTextService, kChinese, GUID_PROFILE_GY_PINYIN, TF_URP_ALLPROFILES);
    wchar_t path[MAX_PATH]{}; GetModuleFileNameW(g_module, path, MAX_PATH);
    const std::wstring name = L"GY 输入法（拼音）";
    std::wstring icon_path = ModuleDirectory() + L"\\gy.ico";
    if (GetFileAttributesW(icon_path.c_str()) == INVALID_FILE_ATTRIBUTES) icon_path = path;
    hr = profiles->RegisterProfile(CLSID_GyTextService, kChinese, GUID_PROFILE_GY_PINYIN,
                                   name.c_str(), static_cast<ULONG>(name.size()), icon_path.c_str(),
                                   static_cast<ULONG>(icon_path.size()), 0, nullptr, 0, TRUE, 0);
  }
  profiles->Release();
  return hr;
}
// A plain TIP_KEYBOARD registration cannot activate in the Windows 11 console
// or Windows Terminal input stack. Register the same capability categories the
// inbox Chinese TIPs carry so the text service is offered there as well.
const GUID kTipCategories[] = {kCategoryTipKeyboard, kCategoryImmersiveSupport, kCategorySystraySupport,
                               kCategoryUiElementEnabled, kCategoryComLess};
HRESULT RegisterCategory(bool remove) {
  ITfCategoryMgr* categories = nullptr;
  HRESULT hr = CoCreateInstance(CLSID_TF_CategoryMgr, nullptr, CLSCTX_INPROC_SERVER, IID_ITfCategoryMgr, reinterpret_cast<void**>(&categories));
  if (FAILED(hr)) return hr;
  for (const GUID& category : kTipCategories) {
    hr = remove ? categories->UnregisterCategory(CLSID_GyTextService, category, CLSID_GyTextService) : categories->RegisterCategory(CLSID_GyTextService, category, CLSID_GyTextService); if (FAILED(hr)) break; }
  categories->Release(); return hr;
}
}  // namespace

extern "C" BOOL WINAPI DllMain(HINSTANCE instance, DWORD reason, LPVOID) { if (reason == DLL_PROCESS_ATTACH) { g_module = instance; DisableThreadLibraryCalls(instance); } return TRUE; }
extern "C" HRESULT WINAPI DllCanUnloadNow() { return S_FALSE; }
extern "C" HRESULT WINAPI DllGetClassObject(REFCLSID clsid, REFIID iid, void** object) { if (clsid != CLSID_GyTextService) return CLASS_E_CLASSNOTAVAILABLE; auto* factory = new ClassFactory(); const HRESULT hr = factory->QueryInterface(iid, object); factory->Release(); return hr; }
extern "C" HRESULT WINAPI DllRegisterServer() { const HRESULT init = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED); const HRESULT com_hr = RegisterComServer(false); const HRESULT profile_hr = SUCCEEDED(com_hr) ? RegisterProfile(false) : com_hr; const HRESULT category_hr = SUCCEEDED(profile_hr) ? RegisterCategory(false) : profile_hr; if (SUCCEEDED(init)) CoUninitialize(); return FAILED(com_hr) ? com_hr : (FAILED(profile_hr) ? profile_hr : category_hr); }
extern "C" HRESULT WINAPI DllUnregisterServer() { const HRESULT init = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED); const HRESULT profile_hr = RegisterProfile(true); const HRESULT category_hr = RegisterCategory(true); const HRESULT com_hr = RegisterComServer(true); if (SUCCEEDED(init)) CoUninitialize(); return FAILED(profile_hr) ? profile_hr : (FAILED(category_hr) ? category_hr : com_hr); }



