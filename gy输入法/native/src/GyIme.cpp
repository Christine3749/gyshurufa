#include <windows.h>
#include <msctf.h>
#include <inputscope.h>

#include <algorithm>
#include <array>
#include <atomic>
#include <memory>
#include <limits>
#include <iterator>
#include <string>
#include <utility>
#include <vector>

#include "SelectionCallback.h"
#include "CandidateLayout.h"
#include "CandidatePresentationPolicy.h"
#include "CorrectionPolicy.h"
#include "EnglishAssist.h"
#include "EnglishAssistPolicy.h"
#include "EnglishCandidatePolicy.h"
#include "Guids.h"
#include "HostedPinyinEngine.h"
#include "InputCapturePolicy.h"
#include "InputMode.h"
#include "InputScopeCache.h"
#include "InputScopePolicy.h"
#include "KeyPolicy.h"
#include "NumericEntryPolicy.h"
#include "PunctuationPolicy.h"
#include "TsfEditSessionPolicy.h"

namespace {
constexpr unsigned kCandidatesPerPage = gy::candidate_presentation::CompactCapacity();
constexpr unsigned kToggleModeAction = std::numeric_limits<unsigned>::max();
constexpr unsigned kPreviousPageAction = kToggleModeAction - 1;
constexpr unsigned kNextPageAction = kToggleModeAction - 2;
constexpr unsigned kToggleChineseGridAction = kToggleModeAction - 3;
constexpr unsigned kPreviousChineseGridPageAction = kToggleModeAction - 4;
constexpr unsigned kNextChineseGridPageAction = kToggleModeAction - 5;
constexpr unsigned kToggleEnglishListAction = kToggleModeAction - 6;
constexpr unsigned kExpandedCandidatesPerPage = gy::candidate_layout::ExpandedCapacity();
constexpr GUID kGuidPropInputScope = {
    0x1713dd5a, 0x68e7, 0x4a5b, {0x9a, 0xf6, 0x59, 0x2a, 0x59, 0x5c, 0x77, 0x8d}};
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

std::wstring SharedIconPath() {
  // The TSF DLL is version-isolated under <install>\\tsf-<version>, but the
  // Windows input-indicator cache must not retain a versioned icon path that
  // disappears when the next release is activated. Keep the registered icon
  // at the stable install root and retain versioned copies for validation and
  // the Host UI.
  const std::wstring module_directory = ModuleDirectory();
  const size_t separator = module_directory.find_last_of(L"\\/");
  return separator == std::wstring::npos
      ? std::wstring{}
      : module_directory.substr(0, separator) + L"\\gy.ico";
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

#ifdef GY_REGISTRATION_TRACE
void TraceRegistration(const wchar_t* stage, HRESULT result) {
  wchar_t temp[MAX_PATH]{};
  if (!GetTempPathW(MAX_PATH, temp)) return;
  const std::wstring path = std::wstring(temp) + L"GyIme.registration.log";
  const HANDLE file = CreateFileW(path.c_str(), FILE_APPEND_DATA, FILE_SHARE_READ | FILE_SHARE_WRITE,
                                  nullptr, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) return;
  wchar_t line[160]{};
  const int length = swprintf_s(line, L"stage=%ls hr=0x%08lX\r\n", stage,
                                 static_cast<unsigned long>(result));
  DWORD written = 0;
  if (length > 0) WriteFile(file, line, static_cast<DWORD>(length * sizeof(wchar_t)), &written, nullptr);
  CloseHandle(file);
}
#else
void TraceRegistration(const wchar_t*, HRESULT) {}
#endif

HRESULT SetRegString(HKEY key, const wchar_t* name, const std::wstring& value) {
  const LSTATUS status = RegSetValueExW(key, name, 0, REG_SZ, reinterpret_cast<const BYTE*>(value.c_str()),
                                        static_cast<DWORD>((value.size() + 1) * sizeof(wchar_t)));
  TraceRegistration(name ? name : L"(default)", HRESULT_FROM_WIN32(status));
  return status == ERROR_SUCCESS ? S_OK : HRESULT_FROM_WIN32(status);
}

enum class EditActionKind {
  Append,
  InsertText,
  Backspace,
  CommitCandidate,
  CommitRaw,
  CancelAndToggleEnglish,
  BeginEnglishAssist,
  DismissEnglishSuggestions,
  Cancel,
  CommitRawForDirectInput,
  RefreshInputScope
};
struct EditAction {
  EditActionKind kind;
  wchar_t character = 0;
  unsigned index = 0;
  unsigned long long mode_generation = 0;
  unsigned long long candidate_input_generation = 0;
  bool explicit_selection = false;
  bool numeric_fragment = false;
  wchar_t trailing_character = 0;
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

class GyTextService final : public ITfTextInputProcessorEx,
                            public ITfKeyEventSink,
                            public ITfThreadMgrEventSink,
                            public ITfCompositionSink,
                            public ITfTextEditSink {
public:
  GyTextService() : engine_(ModuleDirectory()), selection_callback_(g_module, [this](unsigned action) { return HandleHostAction(action); }) {}
  ~GyTextService() { Deactivate(); }
  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid, void** object) override {
    if (!object) return E_INVALIDARG; *object = nullptr;
    if (iid == IID_IUnknown || iid == IID_ITfTextInputProcessor || iid == IID_ITfTextInputProcessorEx) *object = static_cast<ITfTextInputProcessorEx*>(this);
    else if (iid == IID_ITfKeyEventSink) *object = static_cast<ITfKeyEventSink*>(this);
    else if (iid == IID_ITfThreadMgrEventSink) *object = static_cast<ITfThreadMgrEventSink*>(this);
    else if (iid == IID_ITfCompositionSink) *object = static_cast<ITfCompositionSink*>(this);
    else if (iid == IID_ITfTextEditSink) *object = static_cast<ITfTextEditSink*>(this);
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
    UnadviseContextEditSink();
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
    if (!focused) {
      CancelComposition();
      input_scope_known_ = false;
      input_scope_direct_ = false;
      input_scope_sensitive_ = false;
      input_scope_manual_override_ = false;
    } else {
      RequestInputScopeRefresh();
      SynchronizeInputMode(false);
    }
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE OnTestKeyDown(ITfContext* context, WPARAM key, LPARAM, BOOL* eaten) override {
    ReconcileModifierState();
    if (!eaten) return E_INVALIDARG;
    // A native password/PIN control is a synchronous, local hard boundary.
    // Do this before consulting the previous TSF context or any cached scope:
    // on a focus switch Windows can route the first character while the old
    // document context is still current. That first character must never be
    // turned into pinyin or a mode shortcut.
    if (IsNativePasswordControlFocused()) {
      EnterNativeSensitiveDirectMode();
      *eaten = FALSE;
      return S_OK;
    }
    RefreshInputScopeForKey(context, key);
    const bool allow_direct_shift_override = IsShiftKey(key) && AllowsAutoDirectChineseOverride();
    if (EffectiveInputScopeDirect() && !allow_direct_shift_override) { *eaten = FALSE; return S_OK; }
    if (gy::keys::ShouldMarkShiftUsed(shift_down_, key)) shift_used_ = true;
    SynchronizeInputMode(false);
    *eaten = IsEnglishAssistShortcut(key) || ShouldCaptureEnglishAssistKey(key) ||
             (IsShiftKey(key) ? gy::keys::ShouldCaptureShift(HasShortcutModifier()) : ShouldEat(key));
    if (key >= 'A' && key <= 'Z') Trace(L"key.test", S_OK, key);
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE OnTestKeyUp(ITfContext* context, WPARAM key, LPARAM, BOOL* eaten) override {
    if (!eaten) return E_INVALIDARG;
    if (IsNativePasswordControlFocused()) {
      EnterNativeSensitiveDirectMode();
      *eaten = FALSE;
      return S_OK;
    }
    RefreshInputScopeForKey(context, key);
    const bool allow_direct_shift_override = IsShiftKey(key) && AllowsAutoDirectChineseOverride();
    if (EffectiveInputScopeDirect() && !allow_direct_shift_override) { *eaten = FALSE; return S_OK; }
    // A focus switch can leave a cached Ctrl/Alt/Win state behind. Reconcile
    // before deciding whether a plain Shift release is the GY mode toggle.
    ReconcileModifierState();
    *eaten = IsShiftKey(key) && gy::keys::ShouldCaptureShift(HasShortcutModifier());
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE OnKeyDown(ITfContext* context, WPARAM key, LPARAM, BOOL* eaten) override {
    if (!eaten) return E_INVALIDARG;
    *eaten = FALSE;
    if (IsNativePasswordControlFocused()) {
      EnterNativeSensitiveDirectMode();
      return S_OK;
    }
    RefreshInputScopeForKey(context, key);
    const bool allow_direct_shift_override = IsShiftKey(key) && AllowsAutoDirectChineseOverride();
    if (EffectiveInputScopeDirect() && !allow_direct_shift_override) return S_OK;
    if (IsShiftKey(key)) { shift_down_ = true; shift_used_ = HasShortcutModifier(); return S_OK; }
    if (shift_down_) shift_used_ = true;
    UpdateModifierState(key, true);
    ReconcileModifierState();
    SynchronizeInputMode(false);
    Trace(L"key.down", S_OK, key);

    // A learning undo is valid only for the very next ordinary editing key:
    // if the user keeps typing, moves around, or opens a shortcut, do not let
    // a later Backspace rewrite their long-term preference by surprise.
    if (key != VK_BACK && !IsShiftKey(key) && key != VK_CONTROL && key != VK_MENU &&
        key != VK_LWIN && key != VK_RWIN) {
      last_explicit_learn_ = {};
    }

    if (IsEnglishAssistShortcut(key)) {
      if (!english_assist_active_ && IsEnglishAssistAllowed()) {
        SetContext(context);
        *eaten = TRUE;
        return RequestEdit({EditActionKind::BeginEnglishAssist});
      }
      return S_OK;
    }
    if (english_assist_active_ && HandleEnglishAssistKey(context, key)) {
      *eaten = TRUE;
      return S_OK;
    }

    // Shift alone changes the GY conversion mode. Ctrl+Space and other
    // application shortcuts are deliberately passed through untouched.
    const bool english_boundary = gy::input_mode::IsEnglish(input_mode_) &&
        !HasShortcutModifier() && !composition_text_.empty() &&
        EnglishPunctuation(key, IsDown(VK_SHIFT) || shift_down_) != 0;
    if (!english_boundary && !ShouldEat(key)) return S_OK;
    SetContext(context);
    *eaten = TRUE;
    if (const wchar_t punctuation = ChinesePunctuation(key); punctuation != 0) {
      Trace(L"key.punctuation", S_OK, key);
      return RequestEdit({EditActionKind::InsertText, punctuation});
    }
    if (english_boundary) {
      return RequestEdit({EditActionKind::InsertText,
                          EnglishPunctuation(key, IsDown(VK_SHIFT) || shift_down_)});
    }
    // A number fragment is always literal, even while the saved global mode
    // is Simplified or Traditional.  Starting with a digit activates only
    // this in-memory fragment; typing a letter immediately resumes Chinese
    // composition.  We never inspect prior field content.
    const bool shift = IsDown(VK_SHIFT) || shift_down_;
    const wchar_t numeric = composition_text_.empty()
        ? gy::numeric_entry::CharacterFor(key, shift, numeric_fragment_active_)
        : 0;
    if (numeric != 0) {
      EditAction action{EditActionKind::InsertText, numeric};
      action.numeric_fragment = true;
      return RequestEdit(action);
    }
    if (key >= 'A' && key <= 'Z') {
      wchar_t character = static_cast<wchar_t>(key - 'A' + L'a');
      if (gy::input_mode::IsEnglish(input_mode_)) {
        const bool capital = (IsDown(VK_SHIFT) || shift_down_) !=
            ((GetKeyState(VK_CAPITAL) & 1) != 0);
        character = capital ? static_cast<wchar_t>(key) : character;
      }
      return RequestEdit({EditActionKind::Append, character});
    }
    if (key == VK_OEM_7) return RequestEdit({EditActionKind::Append, L'\''});
    if (key == VK_BACK) return RequestEdit({EditActionKind::Backspace});
    if (key == VK_ESCAPE) {
      return gy::input_mode::IsEnglish(input_mode_)
          ? RequestEdit({EditActionKind::DismissEnglishSuggestions})
          : RequestEdit({EditActionKind::Cancel});
    }
    // EN keeps acceptance explicit. Tab accepts the highlighted completion;
    // arrows only move/focus. Space remains literal in the passive strip, but
    // after an explicit arrow action it accepts the highlighted word plus the
    // normal word-boundary space. Enter always preserves the literal token.
    if (gy::input_mode::IsEnglish(input_mode_) && key == VK_TAB && !candidates_.empty()) {
      english_candidate_set_.selection_locked = true;
      return RequestEdit({EditActionKind::CommitCandidate, 0, selected_});
    }
    if (gy::input_mode::IsEnglish(input_mode_) && key == VK_SPACE) {
      if (gy::keys::ShouldAcceptEnglishWithSpace(english_candidate_focus_) && !candidates_.empty()) {
        EditAction action{EditActionKind::CommitCandidate, 0, selected_};
        action.trailing_character = L' ';
        english_candidate_set_.selection_locked = true;
        return RequestEdit(action);
      }
      EditAction action{EditActionKind::CommitRaw};
      action.trailing_character = L' ';
      return RequestEdit(action);
    }
    if (gy::input_mode::IsEnglish(input_mode_) && key == VK_RETURN) {
      EditAction action{EditActionKind::CommitRaw};
      action.trailing_character = L'\r';
      return RequestEdit(action);
    }
    // In the compact Chinese strip Enter preserves the established raw-pinyin
    // path. Once the user explicitly opens the 5 x 5 grid, Enter and Space
    // both commit the currently highlighted candidate.
    if (gy::keys::ShouldCommitSelectedCandidate(key, chinese_grid_open_)) {
      EditAction action{EditActionKind::CommitCandidate, 0, selected_};
      // A default first-item Space/Enter confirmation is intentionally not a
      // learning signal. A moved grid selection is an explicit choice.
      action.explicit_selection = chinese_grid_open_ && selected_ != 0;
      return RequestEdit(action);
    }
    if (gy::keys::IsRawTextCommitKey(key)) return RequestEdit({EditActionKind::CommitRaw});
    // Digits are literal text in EN. They are never candidate shortcuts.
    if (gy::input_mode::IsEnglish(input_mode_) && key >= '0' && key <= '9') {
      return RequestEdit({EditActionKind::Append, static_cast<wchar_t>(key)});
    }
    if (key >= '1' && key <= '5') {
      unsigned candidate_index = page_start_ + static_cast<unsigned>(key - '1');
      if (chinese_grid_open_) {
        candidate_index = gy::candidate_layout::ExpandedDigitCandidate(
            selected_, page_start_, static_cast<unsigned>(candidates_.size()),
            static_cast<unsigned>(key - '0'));
      }
      // The short final row has no hidden candidate behind a missing column.
      // Keep the digit consumed while composition is active, but never commit
      // a different item than the user asked for.
      if (candidate_index >= candidates_.size()) return S_OK;
      EditAction action{EditActionKind::CommitCandidate, 0, candidate_index};
      action.explicit_selection = true;
      return RequestEdit(action);
    }
    if (!gy::input_mode::IsEnglish(input_mode_) && key == VK_PRIOR) {
      MovePage(-1, PageSizeForCurrentView());
      ShowCandidates(context_, nullptr);
      return S_OK;
    }
    if (key == VK_UP) {
      if (gy::input_mode::IsEnglish(input_mode_)) {
        if (!english_list_open_ || candidates_.empty()) return S_OK;
        english_candidate_focus_ = true;
        english_candidate_set_.selection_locked = true;
        MoveEnglishSelection(-1, gy::english_candidates::kExpandedVisible);
        ShowCandidates(context_, nullptr);
        return S_OK;
      }
      if (chinese_grid_open_) {
        // The first ↑ on page one is the deliberate exit gesture. On later
        // pages, ↑ continues to the prior 5 × 5 page in the same column.
        if (page_start_ == 0 && selected_ < kCandidatesPerPage) {
          chinese_grid_open_ = false;
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
    if (!gy::input_mode::IsEnglish(input_mode_) && key == VK_NEXT) {
      MovePage(1, PageSizeForCurrentView());
      ShowCandidates(context_, nullptr);
      return S_OK;
    }
    if (key == VK_DOWN) {
      if (gy::input_mode::IsEnglish(input_mode_)) {
        if (candidates_.empty()) return S_OK;
        english_candidate_focus_ = true;
        english_candidate_set_.selection_locked = true;
        if (!english_list_open_ && gy::candidate_presentation::CanExpandEnglish(
                CurrentCandidatePurpose(), static_cast<unsigned>(candidates_.size()))) {
          english_list_open_ = true;
          selected_ = std::min<unsigned>(selected_, gy::english_candidates::kCompactVisible - 1);
        } else {
          MoveEnglishSelection(1, english_list_open_
              ? gy::english_candidates::kExpandedVisible
              : gy::english_candidates::kCompactVisible);
        }
        ShowCandidates(context_, nullptr);
        return S_OK;
      }
      if (!chinese_grid_open_) {
        if (gy::candidate_presentation::CanExpand(
                CurrentCandidatePurpose(), static_cast<unsigned>(candidates_.size()))) {
          chinese_grid_open_ = true;
          const unsigned page_size = PageSizeForCurrentView();
          page_start_ = selected_ / page_size * page_size;
        } else {
          MoveSelection(1);
        }
      } else {
        selected_ = gy::candidate_layout::MoveExpandedDown(
            selected_, page_start_, static_cast<unsigned>(candidates_.size()));
        page_start_ = selected_ / kExpandedCandidatesPerPage * kExpandedCandidatesPerPage;
      }
      ShowCandidates(context_, nullptr);
      return S_OK;
    }
    if (key == VK_LEFT) {
      if (gy::input_mode::IsEnglish(input_mode_)) {
        english_candidate_focus_ = true;
        english_candidate_set_.selection_locked = true;
        MoveEnglishSelection(-1, english_list_open_
            ? gy::english_candidates::kExpandedVisible
            : gy::english_candidates::kCompactVisible);
      } else if (chinese_grid_open_) {
        selected_ = gy::candidate_layout::MoveExpandedLeft(
            selected_, page_start_, static_cast<unsigned>(candidates_.size()));
      } else {
        MoveSelection(-1);
      }
      ShowCandidates(context_, nullptr);
      return S_OK;
    }
    if (key == VK_RIGHT) {
      if (gy::input_mode::IsEnglish(input_mode_)) {
        english_candidate_focus_ = true;
        english_candidate_set_.selection_locked = true;
        MoveEnglishSelection(1, english_list_open_
            ? gy::english_candidates::kExpandedVisible
            : gy::english_candidates::kCompactVisible);
      } else if (chinese_grid_open_) {
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
    if (IsNativePasswordControlFocused()) {
      EnterNativeSensitiveDirectMode();
      return S_OK;
    }
    const bool allow_direct_shift_override = IsShiftKey(key) && AllowsAutoDirectChineseOverride();
    if (EffectiveInputScopeDirect() && !allow_direct_shift_override) return S_OK;
    // Use real keyboard state so a return from another app cannot suppress a
    // bare-Shift Chinese/English toggle.
    ReconcileModifierState();
    SynchronizeInputMode(false);
    const bool should_toggle = IsShiftKey(key) && gy::keys::ShouldToggleMode(shift_down_, shift_used_, HasShortcutModifier());
    if (IsShiftKey(key)) shift_down_ = false;
    UpdateModifierState(key, false);
    // Backspace remains owned by the target application, so the character is
    // really deleted before we undo its immediately preceding explicit learn.
    // The Host write is fire-and-forget with a 12ms hard deadline.
    if (key == VK_BACK && last_explicit_learn_.active) {
      engine_.UndoLearn(last_explicit_learn_.pinyin, last_explicit_learn_.candidate,
                        last_explicit_learn_.input_mode);
      last_explicit_learn_ = {};
    }
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
    RequestInputScopeRefresh();
    input_scope_cache_.Attach();
    SynchronizeInputMode(false);
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE OnPushContext(ITfContext*) override { return S_OK; }
  HRESULT STDMETHODCALLTYPE OnPopContext(ITfContext*) override { return S_OK; }
  HRESULT STDMETHODCALLTYPE OnEndEdit(ITfContext* context, TfEditCookie cookie, ITfEditRecord*) override {
    if (context == context_) RefreshInputScope(context, cookie);
    return S_OK;
  }
  HRESULT ApplyEdit(ITfContext* edit_context, const EditAction& action, TfEditCookie cookie) {
    // A request posted by a window that has already lost focus must not edit the new window.
    if (!edit_context || edit_context != context_) return S_OK;
    if (action.kind == EditActionKind::RefreshInputScope) {
      RefreshInputScope(edit_context, cookie);
      return S_OK;
    }
    // Once a mode transition happened, ordinary queued work from the old mode
    // is stale. Lifecycle work is different: an accepted cancel must end the
    // old composition, and late URL-scope discovery must preserve its first
    // captured character as literal text even after the direct-mode change.
    const bool lifecycle_edit = action.kind == EditActionKind::Cancel ||
        action.kind == EditActionKind::CommitRawForDirectInput;
    if (!gy::tsf_edit_session::ShouldApply(
            lifecycle_edit, action.mode_generation, mode_generation_)) return S_OK;
    if (action.kind == EditActionKind::BeginEnglishAssist) {
      return BeginEnglishAssist(edit_context, cookie);
    }
    if (action.kind == EditActionKind::DismissEnglishSuggestions) {
      candidates_.clear();
      english_candidate_set_ = {};
      correction_indices_.clear();
      selected_ = 0;
      page_start_ = 0;
      english_candidate_focus_ = false;
      english_list_open_ = false;
      engine_.HideCandidates();
      return S_OK;
    }
    if (action.kind == EditActionKind::InsertText) {
      last_explicit_learn_ = {};
      HRESULT hr = S_OK;
      if (composition_) {
        hr = CommitComposition(edit_context, cookie, selected_,
                               gy::keys::ShouldCommitRawBeforeBoundary(
                                   gy::input_mode::IsEnglish(input_mode_)));
      }
      if (FAILED(hr)) return hr;
      numeric_fragment_active_ = action.numeric_fragment;
      last_commit_was_ascii_ = action.character >= L'0' && action.character <= L'9';
      return InsertText(edit_context, cookie, action.character);
    }
    if (action.kind == EditActionKind::Append) {
      last_explicit_learn_ = {};
      numeric_fragment_active_ = false;
      if (!composition_ && composition_text_.empty()) ResetLearnedPhrase();
      composition_text_ += action.character;
      RefreshCandidates();
      selected_ = 0;
      page_start_ = 0;
      chinese_grid_open_ = false;
      english_candidate_focus_ = false;
      english_list_open_ = false;
      return UpdateComposition(edit_context, cookie);
    }
    if (action.kind == EditActionKind::Backspace) {
      if (!composition_text_.empty()) composition_text_.pop_back();
      RefreshCandidates();
      selected_ = 0;
      page_start_ = 0;
      chinese_grid_open_ = false;
      english_candidate_focus_ = false;
      english_list_open_ = false;
      return composition_text_.empty() ? ClearComposition(cookie) : UpdateComposition(edit_context, cookie);
    }
    if (action.kind == EditActionKind::CommitCandidate) {
      if (gy::input_mode::IsEnglish(input_mode_) && !english_assist_active_ &&
          !gy::english_candidates::CanCommitCandidate(
              action.candidate_input_generation, english_candidate_set_.input_generation)) {
        return S_OK;
      }
      const HRESULT hr = CommitComposition(edit_context, cookie, action.index, false,
                                           action.explicit_selection);
      if (FAILED(hr) || action.trailing_character == 0) return hr;
      return InsertText(edit_context, cookie, action.trailing_character);
    }
    if (action.kind == EditActionKind::CommitRaw) {
      const HRESULT hr = CommitComposition(edit_context, cookie, 0, true);
      if (FAILED(hr) || action.trailing_character == 0) return hr;
      return InsertText(edit_context, cookie, action.trailing_character);
    }
    if (action.kind == EditActionKind::CommitRawForDirectInput) {
      // Firefox exposes mozAwesomebar as IS_URL only after the first edit. The
      // first letter is already a GY composition by then. End that composition
      // as raw text so "www" never becomes "ww" and the text store is unlocked
      // before subsequent literal keys arrive.
      return CommitComposition(edit_context, cookie, 0, true);
    }
    if (action.kind == EditActionKind::CancelAndToggleEnglish) {
      const HRESULT hr = ClearComposition(cookie);
      if (SUCCEEDED(hr)) SetInputMode(gy::input_mode::kEnglish);
      return hr;
    }
    // Unlike unconfirmed pinyin, English Assist starts from text the user has
    // already selected. Esc and lifecycle cancellation must preserve that
    // original text; only an explicit candidate commit may replace it.
    if (english_assist_active_) return CommitComposition(edit_context, cookie, 0, true);
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
  static bool IsAsciiText(const std::wstring& text) {
    return !text.empty() && std::all_of(text.begin(), text.end(), [](wchar_t character) {
      return character >= 0x20 && character <= 0x7e;
    });
  }
  bool IsAsciiTextKey(WPARAM key) const {
    const bool shift = IsDown(VK_SHIFT) || shift_down_;
    return (key >= 'A' && key <= 'Z') || (key >= '0' && key <= '9') ||
           gy::punctuation::IsPunctuationKey(key, shift);
  }
  static wchar_t EnglishPunctuation(WPARAM key, bool shift) {
    switch (key) {
      case VK_OEM_1: return shift ? L':' : L';';
      case VK_OEM_PLUS: return shift ? L'+' : L'=';
      case VK_OEM_COMMA: return shift ? L'<' : L',';
      case VK_OEM_MINUS: return shift ? L'_' : L'-';
      case VK_OEM_PERIOD: return shift ? L'>' : L'.';
      case VK_OEM_2: return shift ? L'?' : L'/';
      case VK_OEM_3: return shift ? L'~' : L'`';
      case VK_OEM_4: return shift ? L'{' : L'[';
      case VK_OEM_5: return shift ? L'|' : L'\\';
      case VK_OEM_6: return shift ? L'}' : L']';
      case VK_OEM_7: return shift ? L'\"' : L'\'';
      default: return 0;
    }
  }
  bool IsControlDown() const {
    return control_down_ || IsDown(VK_CONTROL) || IsDown(VK_LCONTROL) || IsDown(VK_RCONTROL) ||
        IsPhysicallyDown(VK_CONTROL) || IsPhysicallyDown(VK_LCONTROL) || IsPhysicallyDown(VK_RCONTROL);
  }
  bool IsAltDown() const {
    return alt_down_ || IsDown(VK_MENU) || IsDown(VK_LMENU) || IsDown(VK_RMENU) ||
        IsPhysicallyDown(VK_MENU) || IsPhysicallyDown(VK_LMENU) || IsPhysicallyDown(VK_RMENU);
  }
  bool HasShortcutModifier() const {
    return IsControlDown() || alt_down_ || win_down_ || IsDown(VK_MENU) || IsDown(VK_LWIN) || IsDown(VK_RWIN) ||
        IsPhysicallyDown(VK_MENU) || IsPhysicallyDown(VK_LWIN) || IsPhysicallyDown(VK_RWIN);
  }
  static std::wstring CurrentProcessExecutable() {
    wchar_t path[MAX_PATH]{};
    if (!GetModuleFileNameW(nullptr, path, static_cast<DWORD>(std::size(path)))) return {};
    const wchar_t* executable = wcsrchr(path, L'\\');
    executable = executable ? executable + 1 : path;
    return executable;
  }
  bool IsEnglishAssistAllowed() const {
    const std::wstring executable = CurrentProcessExecutable();
    return gy::english_assist::CanActivate(gy::english_assist::IsEnabled(),
                                           gy::input_mode::IsEnglish(input_mode_),
                                           input_scope_direct_,
                                           executable);
  }
  bool IsEnglishAssistShortcut(WPARAM key) const {
    return key == VK_OEM_PERIOD && IsControlDown() && IsAltDown() &&
           !win_down_ && IsEnglishAssistAllowed();
  }
  bool ShouldCaptureEnglishAssistKey(WPARAM key) const {
    if (!english_assist_active_) return false;
    return key == VK_ESCAPE || key == VK_RETURN || key == VK_TAB ||
           key == VK_LEFT || key == VK_RIGHT;
  }
  bool HandleEnglishAssistKey(ITfContext* context, WPARAM key) {
    if (!english_assist_active_) return false;
    if (key == VK_ESCAPE) return SUCCEEDED(RequestEdit({EditActionKind::Cancel}));
    if (key == VK_RETURN || key == VK_TAB) {
      return SUCCEEDED(RequestEdit({EditActionKind::CommitCandidate, 0, selected_}));
    }
    if (key == VK_LEFT || key == VK_RIGHT) {
      MoveSelection(key == VK_LEFT ? -1 : 1);
      ShowCandidates(context, nullptr);
      return true;
    }
    return false;
  }
  unsigned CurrentPageCandidateCount() const {
    if (page_start_ >= candidates_.size()) return 0;
    return std::min<unsigned>(kCandidatesPerPage,
                              static_cast<unsigned>(candidates_.size()) - page_start_);
  }
  gy::candidate_presentation::Purpose CurrentCandidatePurpose() const {
    if (english_assist_active_) return gy::candidate_presentation::Purpose::EnglishCorrection;
    return gy::input_mode::IsEnglish(input_mode_)
        ? gy::candidate_presentation::Purpose::EnglishCompletion
        : gy::candidate_presentation::Purpose::ChineseConversion;
  }
  unsigned PageSizeForCurrentView() const {
    const auto surface = gy::candidate_presentation::Resolve(
        CurrentCandidatePurpose(), chinese_grid_open_, static_cast<unsigned>(candidates_.size()),
        false, english_list_open_);
    return gy::candidate_presentation::PageSize(surface);
  }
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
    // A literal field is an overlay, not a global mode write. A deliberate
    // Shift in a non-sensitive URL/email/path field may temporarily restore
    // Chinese for this focus; Shift again returns to direct EN. Password and
    // PIN fields remain a hard direct-input boundary.
    if (input_scope_direct_) {
      if (input_scope_sensitive_) {
        Trace(L"mode.toggle.sensitive-ignored");
        return;
      }
      input_scope_manual_override_ = !input_scope_manual_override_;
      ApplyInputMode(input_scope_manual_override_ ? chinese_mode_ : gy::input_mode::kEnglish, true);
      return;
    }
    const int next_mode = gy::input_mode::IsEnglish(input_mode_) ? chinese_mode_ : gy::input_mode::kEnglish;
    const bool next_english = gy::input_mode::IsEnglish(next_mode);
    if (gy::keys::ShouldCancelCompositionBeforeModeSwitch(
            composition_ != nullptr && !composition_text_.empty(), next_english)) {
      const HRESULT hr = RequestEdit({EditActionKind::CancelAndToggleEnglish});
      Trace(L"mode.toggle.cancel-composition", hr);
      return;
    }
    SetInputMode(next_mode);
  }
  void MoveEnglishSelection(int delta, unsigned capacity) {
    if (candidates_.empty()) return;
    const unsigned visible = std::min<unsigned>(capacity,
        static_cast<unsigned>(candidates_.size()));
    if (visible == 0) return;
    const int count = static_cast<int>(visible);
    const int current = selected_ < visible ? static_cast<int>(selected_) : 0;
    selected_ = static_cast<unsigned>((current + delta + count) % count);
    page_start_ = 0;
  }
  void SetInputMode(int mode) {
    if (!gy::input_mode::Write(mode)) {
      Trace(L"mode.persist-failed", E_FAIL, mode);
      ApplyInputMode(gy::input_mode::Read(), true);
      return;
    }
    ApplyInputMode(mode, true);
  }
  void ApplyInputMode(int mode, bool announce, bool preserve_raw_for_direct = false) {
    mode = gy::input_mode::Normalize(mode);
    const bool next_english = gy::input_mode::IsEnglish(mode);
    const bool mode_changed = mode != input_mode_ || english_mode_ != next_english;
    const bool has_direct_transition_text =
        gy::tsf_edit_session::ShouldCommitRawForDirectInput(
            preserve_raw_for_direct, !composition_text_.empty());
    if (!mode_changed && !has_direct_transition_text) return;
    ++mode_generation_;
    if (!composition_text_.empty()) {
      if (preserve_raw_for_direct) {
        const HRESULT hr = RequestEdit({EditActionKind::CommitRawForDirectInput});
        // S_OK and TF_S_ASYNC both mean TSF accepted responsibility for ending
        // the composition. Only abandon local state when the request failed.
        if (!gy::tsf_edit_session::WasAccepted(hr)) ResetCompositionState();
      } else {
        CancelComposition();
      }
    }
    input_mode_ = mode;
    if (next_english) chinese_mode_ = gy::input_mode::ReadLastChineseMode();
    else chinese_mode_ = mode;
    english_mode_ = next_english;
    if (announce) engine_.ShowMode(last_caret_, input_mode_);
  }
  void SynchronizeInputMode(bool announce) {
    if (EffectiveInputScopeDirect()) {
      ApplyInputMode(gy::input_mode::kEnglish, false);
      return;
    }
    ApplyInputMode(gy::input_mode::Read(), announce);
  }
  static HWND CurrentFocusedInputWindow() {
    // GetFocus() reports the focus associated with the caller's input queue.
    // A TSF callback can be delivered on a different queue while an app is
    // changing controls, leaving it one key behind. Prefer the foreground
    // window's GUI-thread focus, then fall back to the local value. This only
    // reads window handles/styles; it does not use UI Automation or inspect
    // application text.
    const HWND foreground = GetForegroundWindow();
    if (foreground) {
      GUITHREADINFO info{};
      info.cbSize = sizeof(info);
      const DWORD thread_id = GetWindowThreadProcessId(foreground, nullptr);
      if (thread_id != 0 && GetGUIThreadInfo(thread_id, &info) && info.hwndFocus) {
        return info.hwndFocus;
      }
    }
    return GetFocus();
  }
  static bool IsNativePasswordControlFocused() {
    const HWND focused = CurrentFocusedInputWindow();
    if (!focused) return false;
    wchar_t class_name[64]{};
    if (!GetClassNameW(focused, class_name, static_cast<int>(std::size(class_name)))) return false;
    const bool edit_control = lstrcmpiW(class_name, L"Edit") == 0 ||
                               lstrcmpiW(class_name, L"RichEdit20W") == 0 ||
                               lstrcmpiW(class_name, L"RICHEDIT50W") == 0;
    if (!edit_control) return false;
    return (GetWindowLongPtrW(focused, GWL_STYLE) & ES_PASSWORD) != 0;
  }
  void EnterNativeSensitiveDirectMode() {
    // Never request an edit against an old context from this first-key path.
    // Locally discard stale composition state and tell the Host to hide only
    // the candidate UI; the password text itself is never read or written.
    ResetCompositionState();
    input_scope_known_ = true;
    input_scope_direct_ = true;
    input_scope_sensitive_ = true;
    input_scope_manual_override_ = false;
    input_scope_hwnd_ = CurrentFocusedInputWindow();
    input_scope_probe_count_ = 0;
    ApplyInputMode(gy::input_mode::kEnglish, false);
  }
  struct InputScopeResult {
    bool available = false;
    bool english = false;
    bool sensitive = false;
  };

  static InputScopeResult ReadInputScope(ITfContext* context, TfEditCookie cookie) {
    InputScopeResult result;
    if (!context) return result;
    ITfReadOnlyProperty* property = nullptr;
    if (FAILED(context->GetAppProperty(kGuidPropInputScope, &property))) return result;

    TF_SELECTION selection{};
    ULONG fetched = 0;
    ITfRange* range = nullptr;
    if (SUCCEEDED(context->GetSelection(cookie, TF_DEFAULT_SELECTION, 1, &selection, &fetched)) &&
        fetched == 1 && selection.range) {
      range = selection.range;
    } else {
      context->GetStart(cookie, &range);
    }

    if (range) {
      VARIANT value;
      VariantInit(&value);
      if (SUCCEEDED(property->GetValue(cookie, range, &value)) && value.vt == VT_UNKNOWN && value.punkVal) {
        ITfInputScope* input_scope = nullptr;
        if (SUCCEEDED(value.punkVal->QueryInterface(__uuidof(ITfInputScope),
                                                     reinterpret_cast<void**>(&input_scope)))) {
          InputScope* scopes = nullptr;
          UINT count = 0;
          if (SUCCEEDED(input_scope->GetInputScopes(&scopes, &count)) && scopes) {
            result.available = true;
            for (UINT index = 0; index < count; ++index) {
              if (gy::input_scope::IsEnglishContext(scopes[index])) {
                result.english = true;
              }
              if (gy::input_scope::IsSensitiveDirectInput(scopes[index])) result.sensitive = true;
            }
            CoTaskMemFree(scopes);
          }
          input_scope->Release();
        }
      }
      VariantClear(&value);
      range->Release();
    }
    property->Release();
    return result;
  }

  void ApplyInputScope(bool direct, bool sensitive, bool known) {
    const bool changed = input_scope_known_ != known || input_scope_direct_ != direct ||
                         input_scope_sensitive_ != sensitive;
    if (gy::input_scope::ShouldClearManualChineseOverrideOnScopeChange(
            input_scope_known_, input_scope_direct_, input_scope_sensitive_,
            known, direct, sensitive)) {
      input_scope_manual_override_ = false;
    }
    input_scope_known_ = known;
    input_scope_direct_ = direct;
    input_scope_sensitive_ = sensitive;
    if (!changed) return;
    Trace(L"input-scope.direct", S_OK, direct ? 1 : 0);
    Trace(L"input-scope.sensitive", S_OK, sensitive ? 1 : 0);
    Trace(L"input-scope.known", S_OK, known ? 1 : 0);
    if (EffectiveInputScopeDirect()) {
      // Firefox publishes mozAwesomebar's IS_URL scope from OnEndEdit, after
      // its first letter is already inside a GY composition. Preserve that
      // letter as literal text while switching this field to direct English;
      // deleting it would turn a typed "www" into "ww".
      ApplyInputMode(gy::input_mode::kEnglish, false, !input_scope_sensitive_);
      engine_.HideCandidates();
    } else {
      SynchronizeInputMode(false);
    }
  }
  void RefreshInputScope(ITfContext* context, TfEditCookie cookie) {
    if (!context || context != context_) return;
    const HWND focused = CurrentFocusedInputWindow();
    const bool focus_changed = input_scope_hwnd_ != focused;
    if (focus_changed) {
      input_scope_probe_count_ = 0;
      input_scope_manual_override_ = false;
    }

    const InputScopeResult scope = ReadInputScope(context, cookie);
    const bool native_password = IsNativePasswordControlFocused();
    // UI Automation is deliberately never called from this TSF DLL.  It can
    // cross into a browser/Electron process and block its input thread.  TSF
    // InputScope plus the local native password style are safe, non-content
    // signals; richer browser detection is supplied asynchronously by Host.
    bool cached_direct = false;
    bool cached_sensitive = false;
    const bool has_cached_scope = input_scope_cache_.ReadForCurrentForeground(&cached_direct, &cached_sensitive);
    const bool direct_fallback = native_password || (has_cached_scope && cached_direct);
    const bool sensitive_fallback = native_password || (has_cached_scope && cached_sensitive);
    input_scope_hwnd_ = focused;
    if (scope.available || direct_fallback) {
      input_scope_probe_count_ = 0;
      ApplyInputScope(scope.english || direct_fallback, scope.sensitive || sensitive_fallback, true);
      return;
    }

    // Some browser contexts publish their input scope one edit later. Do not
    // permanently cache that first miss as "ordinary Chinese". On a new
    // focus, fail safe to the user's normal mode and await a later async TSF
    // scope refresh.  No content or cross-process metadata is read here.
    if (focus_changed || !input_scope_known_) ApplyInputScope(false, false, false);
    if (input_scope_probe_count_ < 3) ++input_scope_probe_count_;
  }
  void RequestInputScopeRefresh(ITfContext* context) {
    if (!context || context != context_ || client_id_ == TF_CLIENTID_NULL) return;
    auto* edit = new EditSession(this, context, EditAction{EditActionKind::RefreshInputScope});
    HRESULT session_hr = E_FAIL;
    const HRESULT hr = context->RequestEditSession(client_id_, edit, TF_ES_ASYNC | TF_ES_READ, &session_hr);
    Trace(L"input-scope.refresh", FAILED(hr) ? hr : session_hr);
    edit->Release();
  }
  void RequestInputScopeRefresh() { RequestInputScopeRefresh(context_); }
  void RefreshInputScopeForKey(ITfContext* context, WPARAM key) {
    if (!context || context != context_) return;
    // A password/PIN control must be a hard direct-input boundary from its
    // very first key.  This key-time guard is strictly local: it checks a
    // native password style only.  Any TSF metadata refresh is posted
    // asynchronously, so no user application is synchronously called here.
    const HWND focused = CurrentFocusedInputWindow();
    if (input_scope_hwnd_ != focused || !input_scope_known_ || IsShiftKey(key)) {
      const bool native_password = IsNativePasswordControlFocused();
      if (native_password) {
        ApplyInputScope(true, true, true);
        input_scope_hwnd_ = focused;
        input_scope_probe_count_ = 0;
        return;
      }
    }
    bool cached_direct = false;
    bool cached_sensitive = false;
    if (input_scope_cache_.ReadForCurrentForeground(&cached_direct, &cached_sensitive) && cached_direct) {
      ApplyInputScope(true, cached_sensitive, true);
      input_scope_hwnd_ = focused;
      input_scope_probe_count_ = 0;
      return;
    }
    if (input_scope_hwnd_ != focused) {
      input_scope_known_ = false;
      input_scope_probe_count_ = 0;
    }
    // Scope probes are scheduled on focus and normal edit notifications, not
    // from a key event.  This preserves the input thread's no-wait rule.
  }
  bool HandleHostAction(unsigned action) {
    if (action == kToggleModeAction) {
      ToggleEnglishMode();
    } else if (action == kToggleChineseGridAction) {
      if (gy::input_mode::IsEnglish(input_mode_)) return true;
      chinese_grid_open_ = !chinese_grid_open_ && gy::candidate_presentation::CanExpand(
          CurrentCandidatePurpose(), static_cast<unsigned>(candidates_.size()));
      const unsigned page_size = PageSizeForCurrentView();
      page_start_ = selected_ / page_size * page_size;
      ShowCandidates(context_, nullptr);
    } else if (action == kToggleEnglishListAction) {
      if (!gy::input_mode::IsEnglish(input_mode_)) return true;
      if (candidates_.empty()) return true;
      english_list_open_ = !english_list_open_ && gy::candidate_presentation::CanExpandEnglish(
          CurrentCandidatePurpose(), static_cast<unsigned>(candidates_.size()));
      english_candidate_focus_ = true;
      english_candidate_set_.selection_locked = true;
      selected_ = std::min<unsigned>(selected_, static_cast<unsigned>(candidates_.size() - 1));
      page_start_ = 0;
      ShowCandidates(context_, nullptr);
    } else if (action == kPreviousPageAction) {
      if (gy::input_mode::IsEnglish(input_mode_)) return true;
      MovePage(-1, kCandidatesPerPage);
      ShowCandidates(context_, nullptr);
    } else if (action == kNextPageAction) {
      if (gy::input_mode::IsEnglish(input_mode_)) return true;
      MovePage(1, kCandidatesPerPage);
      ShowCandidates(context_, nullptr);
    } else if (action == kPreviousChineseGridPageAction) {
      if (gy::input_mode::IsEnglish(input_mode_)) return true;
      MovePage(-1, PageSizeForCurrentView());
      ShowCandidates(context_, nullptr);
    } else if (action == kNextChineseGridPageAction) {
      if (gy::input_mode::IsEnglish(input_mode_)) return true;
      MovePage(1, PageSizeForCurrentView());
      ShowCandidates(context_, nullptr);
    } else {
      return Select(action);
    }
    return true;
  }
  wchar_t ChinesePunctuation(WPARAM key) {
    // Pure EN keeps the candidate surface but leaves punctuation as native
    // ASCII text owned by the focused application.
    if (gy::input_mode::IsEnglish(input_mode_)) return 0;
    if (gy::punctuation::ShouldUseEnglishPunctuation(
            gy::input_mode::IsEnglish(input_mode_),
            composition_ != nullptr && !composition_text_.empty(),
            last_commit_was_ascii_) || HasShortcutModifier()) return 0;
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
    if (composition_text_.empty() && gy::numeric_entry::Accepts(
            key, IsDown(VK_SHIFT) || shift_down_, numeric_fragment_active_)) return true;
    return gy::input_capture::ShouldCapture(
        gy::input_mode::IsEnglish(input_mode_), HasShortcutModifier(),
        IsDown(VK_SHIFT) || shift_down_, !composition_text_.empty(),
        CurrentPageCandidateCount(), static_cast<unsigned>(candidates_.size()), key,
        gy::punctuation::ShouldUseEnglishPunctuation(
            gy::input_mode::IsEnglish(input_mode_),
            composition_ != nullptr && !composition_text_.empty(),
            last_commit_was_ascii_), english_list_open_);
  }
  void SetContext(ITfContext* context) {
    if (context == context_) return;
    Trace(L"context.change", S_OK, context ? 1 : 0);
    // The remembered caret belongs to the previous context: an app or document
    // switch must never anchor the candidate window to a position measured
    // somewhere else (it jumped across the screen after an app switch).
    last_caret_valid_ = false;
    composition_anchor_valid_ = false;
    CancelComposition();
    UnadviseContextEditSink();
    input_scope_known_ = false;
    input_scope_direct_ = false;
    input_scope_sensitive_ = false;
    input_scope_manual_override_ = false;
    input_scope_hwnd_ = nullptr;
    input_scope_probe_count_ = 0;
    last_commit_was_ascii_ = false;
    numeric_fragment_active_ = false;
    last_explicit_learn_ = {};
    if (context_) context_->Release();
    context_ = context;
    if (context_) {
      context_->AddRef();
      AdviseContextEditSink();
    }
  }
  void AdviseContextEditSink() {
    if (!context_) return;
    ITfSource* source = nullptr;
    if (SUCCEEDED(context_->QueryInterface(IID_ITfSource, reinterpret_cast<void**>(&source)))) {
      source->AdviseSink(IID_ITfTextEditSink, static_cast<ITfTextEditSink*>(this), &context_edit_sink_);
      source->Release();
    }
  }
  void UnadviseContextEditSink() {
    if (!context_ || context_edit_sink_ == TF_INVALID_COOKIE) return;
    ITfSource* source = nullptr;
    if (SUCCEEDED(context_->QueryInterface(IID_ITfSource, reinterpret_cast<void**>(&source)))) {
      source->UnadviseSink(context_edit_sink_);
      source->Release();
    }
    context_edit_sink_ = TF_INVALID_COOKIE;
  }
  HRESULT RequestEdit(EditAction action) { if (!context_) { Trace(L"edit.no-context", E_FAIL); return E_FAIL; } action.mode_generation = mode_generation_; action.candidate_input_generation = english_candidate_set_.input_generation; auto* edit = new EditSession(this, context_, action); HRESULT session_hr = E_FAIL; const HRESULT hr = context_->RequestEditSession(client_id_, edit, TF_ES_ASYNCDONTCARE | TF_ES_READWRITE, &session_hr); Trace(L"edit.request", FAILED(hr) ? hr : session_hr); edit->Release(); return FAILED(hr) ? hr : session_hr; }
  HRESULT UpdateComposition(ITfContext* edit_context, TfEditCookie cookie) {
    if (!edit_context) return E_FAIL;
    if (!composition_) {
      // Canonical SampleIME path: ask the host for the insertion range with a
      // query-only insert instead of cloning the current selection. XAML hosts
      // (TextInputHost search box, Explorer address bar) assign the range
      // anchors' gravity themselves; a cloned selection collapsed to
      // TF_ANCHOR_END keeps OUR gravity, and those hosts leave the visible
      // caret at the stale anchor after later SetText calls (all S_OK).
      ITfInsertAtSelection* inserter = nullptr;
      HRESULT hr = edit_context->QueryInterface(IID_ITfInsertAtSelection,
                                                reinterpret_cast<void**>(&inserter));
      Trace(L"composition.get-inserter", hr);
      ITfRange* composition_range = nullptr;
      if (SUCCEEDED(hr)) {
        hr = inserter->InsertTextAtSelection(cookie, TF_IAS_QUERYONLY, nullptr, 0,
                                             &composition_range);
        Trace(L"composition.query-insert", hr);
      }

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
      if (inserter) inserter->Release();
      if (FAILED(hr)) return hr;
      if (!composition_) { Trace(L"composition.rejected", E_FAIL); return E_FAIL; }
      // A brand-new composition re-anchors on its first measurement.
      composition_anchor_valid_ = false;
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
  HRESULT BeginEnglishAssist(ITfContext* edit_context, TfEditCookie cookie) {
    // The only text read by English Assist is an active selection supplied by
    // the user through Ctrl+Alt+. No caret-surrounding text, clipboard or field
    // value is collected, and the action is unavailable in direct/sensitive or
    // code/terminal contexts.
    if (!edit_context || english_assist_active_ || !IsEnglishAssistAllowed()) return S_OK;
    TF_SELECTION selection{};
    ULONG fetched = 0;
    HRESULT hr = edit_context->GetSelection(cookie, TF_DEFAULT_SELECTION, 1, &selection, &fetched);
    if (FAILED(hr) || fetched != 1 || !selection.range) return FAILED(hr) ? hr : S_OK;

    std::array<wchar_t, 65> buffer{};
    ULONG copied = 0;
    // Ask for one character beyond the product limit. That distinguishes an
    // exact 64-character selection (valid) from a longer selection without
    // ever reading the rest of the field.
    hr = selection.range->GetText(cookie, 0, buffer.data(),
                                  static_cast<ULONG>(buffer.size()), &copied);
    const std::wstring text(buffer.data(), copied);
    if (FAILED(hr) || copied > 64 || !gy::english_assist::IsEligibleSelection(text)) {
      selection.range->Release();
      return FAILED(hr) ? hr : S_OK;
    }

    std::vector<std::wstring> suggestions = gy::english_assist::Suggest(text);
    if (suggestions.empty()) {
      selection.range->Release();
      return S_OK;
    }

    ITfContextComposition* composer = nullptr;
    hr = edit_context->QueryInterface(IID_ITfContextComposition, reinterpret_cast<void**>(&composer));
    if (SUCCEEDED(hr)) {
      hr = composer->StartComposition(cookie, selection.range,
                                      static_cast<ITfCompositionSink*>(this), &composition_);
    }
    if (composer) composer->Release();
    selection.range->Release();
    if (FAILED(hr) || !composition_) return FAILED(hr) ? hr : E_FAIL;

    composition_text_ = text;
    candidates_ = std::move(suggestions);
    correction_indices_.clear();
    selected_ = 0;
    page_start_ = 0;
    chinese_grid_open_ = false;
    english_candidate_focus_ = false;
    english_list_open_ = false;
    english_assist_active_ = true;
    ITfRange* range = nullptr;
    hr = composition_->GetRange(&range);
    if (SUCCEEDED(hr) && range) {
      hr = range->SetText(cookie, 0, composition_text_.c_str(), static_cast<LONG>(composition_text_.size()));
      if (SUCCEEDED(hr)) ShowCandidates(edit_context, range, cookie);
      range->Release();
    }
    if (SUCCEEDED(hr) && !range) hr = E_FAIL;
    // This is a selected, already-existing word. If opening the temporary
    // assist composition fails, committing the original is the only safe
    // outcome; ClearComposition would delete the user's selection.
    if (FAILED(hr)) return CommitComposition(edit_context, cookie, 0, true);
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
  HRESULT CommitComposition(ITfContext* edit_context, TfEditCookie cookie, unsigned index,
                            bool raw_text = false, bool explicit_selection = false) {
    if (!composition_) return S_OK;
    const bool selected_candidate = !raw_text && index < candidates_.size();
    const bool english_assist = english_assist_active_;
    const std::wstring pinyin = composition_text_;
    const bool english_candidate = gy::input_mode::IsEnglish(input_mode_);
    const std::wstring text = english_assist
        ? gy::english_assist::ResolveCommitText(composition_text_, candidates_, index, selected_candidate)
        : (selected_candidate && english_candidate && index < english_candidate_set_.candidates.size()
              ? gy::english_candidates::ResolveCommit(composition_text_, english_candidate_set_.candidates[index])
              : (selected_candidate ? candidates_[index] : composition_text_));
    const std::wstring remaining_pinyin = selected_candidate && !english_assist && !english_candidate
        ? engine_.RemainingPinyin(pinyin, text, input_mode_, mode_generation_) : L"";
    std::wstring learned_pinyin = pinyin;
    if (!remaining_pinyin.empty()) {
      const size_t consumed_end = pinyin.size() - remaining_pinyin.size();
      learned_pinyin = pinyin.substr(0, consumed_end);
      while (!learned_pinyin.empty() && learned_pinyin.back() == L'\'') learned_pinyin.pop_back();
    }
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
    composition_anchor_valid_ = false;
    if (SUCCEEDED(hr) && selected_candidate && explicit_selection && !english_assist && !english_candidate) {
      const bool had_previous_segment = !learned_phrase_pinyin_.empty();
      engine_.Learn(learned_pinyin, text, input_mode_);
      last_explicit_learn_ = ExplicitLearn{learned_pinyin, text, input_mode_, true};
      RecordLearnedSegment(learned_pinyin, text);
      // Individual segment learning keeps normal word prediction intact. Once
      // the chained selection reaches the end of the original composition,
      // also remember the complete phrase so the next identical input can
      // promote the user's full sentence instead of replaying only its last
      // selected word.
      if (remaining_pinyin.empty() && had_previous_segment &&
          !learned_phrase_pinyin_.empty() && !learned_phrase_text_.empty()) {
        engine_.Learn(learned_phrase_pinyin_, learned_phrase_text_, input_mode_);
      }
      if (remaining_pinyin.empty()) ResetLearnedPhrase();
    }
    if (SUCCEEDED(hr)) last_commit_was_ascii_ = (raw_text || english_assist || english_candidate) && IsAsciiText(text);
    composition_text_.clear();
    candidates_.clear();
    english_candidate_set_ = {};
    correction_indices_.clear();
    selected_ = 0;
    page_start_ = 0;
    chinese_grid_open_ = false;
    english_candidate_focus_ = false;
    english_list_open_ = false;
    english_assist_active_ = false;
    if (SUCCEEDED(hr) && selected_candidate && !english_assist && !english_candidate && !remaining_pinyin.empty()) {
      // Selecting a prefix candidate must not swallow the unconsumed suffix.
      // Start a fresh TSF composition at the caret after the committed word;
      // UpdateComposition renders the remaining pinyin and its next choices.
      composition_text_ = remaining_pinyin;
      RefreshCandidates();
      if (!candidates_.empty()) {
        const HRESULT next_hr = UpdateComposition(edit_context, cookie);
        if (SUCCEEDED(next_hr)) return hr;
      }
      // If the next composition cannot be opened, leave the committed word
      // intact and fall back to the normal hidden-candidate state.
      composition_text_.clear();
      candidates_.clear();
      english_candidate_set_ = {};
      correction_indices_.clear();
    }
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
  void ResetLearnedPhrase() {
    learned_phrase_pinyin_.clear();
    learned_phrase_text_.clear();
  }
  void RecordLearnedSegment(const std::wstring& pinyin, const std::wstring& text) {
    if (pinyin.empty() || text.empty()) return;
    if (learned_phrase_pinyin_.empty()) {
      learned_phrase_pinyin_ = pinyin;
    } else {
      learned_phrase_pinyin_ += pinyin;
    }
    learned_phrase_text_ += text;
  }
  void ResetCompositionState() {
    if (composition_) { composition_->Release(); composition_ = nullptr; }
    composition_anchor_valid_ = false;
    composition_text_.clear();
    candidates_.clear();
    english_candidate_set_ = {};
    correction_indices_.clear();
    selected_ = 0;
    page_start_ = 0;
    engine_.HideCandidates();
    chinese_grid_open_ = false;
    english_candidate_focus_ = false;
    english_list_open_ = false;
    english_assist_active_ = false;
    ResetLearnedPhrase();
  }
  void CancelComposition() {
    if (composition_ && context_ && client_id_ != TF_CLIENTID_NULL) {
      const HRESULT hr = RequestEdit({EditActionKind::Cancel});
      // TF_S_ASYNC is the normal success result when cancellation is requested
      // from OnEndEdit. Keep the composition object alive for DoEditSession;
      // releasing it here leaves Firefox's text store composing forever.
      if (gy::tsf_edit_session::WasAccepted(hr)) return;
    }
    ResetCompositionState();
  }
  void ShowCandidates(ITfContext* edit_context, ITfRange* known_range, TfEditCookie cookie = TF_INVALID_EDIT_COOKIE) {
    if (candidates_.empty()) { engine_.HideCandidates(); return; }
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
    // Chromium TSF can answer GetTextExt with a stale cached rect for one
    // frame right after an app switch (Kimi: the strip jumped up-left on the
    // second keystroke). Within one composition the anchor must be continuous:
    // left/top stay fixed while only the right edge grows. A larger jump is a
    // bogus measurement — keep the anchor pinned for this composition instead
    // of poisoning last_caret_ with it.
    if (composition_ && have_caret) {
      if (!composition_anchor_valid_) {
        composition_anchor_ = caret;
        composition_anchor_valid_ = true;
      } else {
        const LONG anchor_h = (composition_anchor_.bottom - composition_anchor_.top) > 1 ? (composition_anchor_.bottom - composition_anchor_.top) : 1;
        const LONG dx = caret.left - composition_anchor_.left;
        const LONG dy = caret.top - composition_anchor_.top;
        const LONG dy_limit = anchor_h + anchor_h / 2 + 8;  // tolerate a line wrap
        if (dy < -dy_limit || dy > dy_limit || dx < -64 || dx > 96) {
          caret = composition_anchor_;
          last_caret_ = composition_anchor_;
          TraceRect(L"caret.clamp", caret);
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
    const unsigned candidate_purpose = static_cast<unsigned>(CurrentCandidatePurpose());
    engine_.ShowCandidates(caret, composition_text_, candidates_, selected_, page_start_, input_mode_,
                           candidate_purpose, chinese_grid_open_, english_list_open_,
                           english_candidate_focus_,
                           selection_callback_.Endpoint(),
                           correction_indices_);
  }
  bool Select(unsigned index) {
    if (index >= candidates_.size()) return false;
    if (gy::input_mode::IsEnglish(input_mode_)) {
      english_candidate_set_.selection_locked = true;
    }
    EditAction action{EditActionKind::CommitCandidate, 0, index};
    action.explicit_selection = true;
    return SUCCEEDED(RequestEdit(action));
  }
  void ApplyEnglishAsyncCandidates(
      unsigned long long input_generation,
      std::vector<gy::english_candidates::Candidate> candidates) {
    if (!gy::input_mode::IsEnglish(input_mode_) ||
        !gy::english_candidates::CanApplyAsyncResult(
            input_generation, english_candidate_set_.input_generation,
            english_candidate_set_.selection_locked)) {
      return;
    }
    if (candidates.size() > gy::english_candidates::kMaximumVisible) {
      candidates.resize(gy::english_candidates::kMaximumVisible);
    }
    english_candidate_set_.candidates = std::move(candidates);
    candidates_.clear();
    candidates_.reserve(english_candidate_set_.candidates.size());
    for (const auto& candidate : english_candidate_set_.candidates) {
      candidates_.push_back(candidate.display_text);
    }
    selected_ = 0;
    page_start_ = 0;
    english_list_open_ = false;
    ShowCandidates(context_, nullptr);
  }
  void RefreshCandidates() {
    // Separate from the language-mode generation: every composition refresh
    // gets its own token so a slow prediction for "w" cannot replace the
    // newer candidates for "wo".
    const unsigned long long input_generation = ++candidate_input_generation_;
    const int lookup_mode = input_mode_;
    const unsigned long long lookup_generation = mode_generation_;
    candidates_ = engine_.Lookup(composition_text_, lookup_mode, lookup_generation);
    if (lookup_mode != input_mode_ || lookup_generation != mode_generation_) {
      candidates_.clear();
      english_candidate_set_ = {};
      correction_indices_.clear();
      return;
    }
    english_candidate_set_ = {};
    if (gy::input_mode::IsEnglish(lookup_mode)) {
      english_candidate_set_.candidates =
          gy::english_candidates::CompletionCandidates(composition_text_, candidates_);
      english_candidate_set_.input_generation = input_generation;
      english_candidate_set_.selection_locked = false;
      candidates_.clear();
      candidates_.reserve(english_candidate_set_.candidates.size());
      for (const auto& candidate : english_candidate_set_.candidates) {
        candidates_.push_back(candidate.display_text);
      }
    }
    correction_indices_ = gy::correction::InsertPinyinSpellingCorrection(
        &candidates_, composition_text_, input_mode_);
  }
  bool EffectiveInputScopeDirect() const noexcept {
    return input_scope_direct_ && !input_scope_manual_override_;
  }
  bool AllowsAutoDirectChineseOverride() const noexcept {
    return gy::input_scope::AllowsManualChineseOverride(input_scope_direct_, input_scope_sensitive_);
  }
  struct ExplicitLearn { std::wstring pinyin; std::wstring candidate; int input_mode = -1; bool active = false; };
  std::atomic<ULONG> refs_{1}; ITfThreadMgr* thread_mgr_ = nullptr; ITfKeystrokeMgr* keystroke_mgr_ = nullptr; ITfContext* context_ = nullptr; ITfComposition* composition_ = nullptr; TfClientId client_id_ = TF_CLIENTID_NULL; DWORD thread_mgr_sink_ = TF_INVALID_COOKIE; DWORD context_edit_sink_ = TF_INVALID_COOKIE; HostedPinyinEngine engine_; SelectionCallback selection_callback_; gy::input_scope_cache::Reader input_scope_cache_; RECT last_caret_{0, 0, 360, 24}; bool last_caret_valid_ = false; RECT composition_anchor_{}; bool composition_anchor_valid_ = false; std::wstring composition_text_; std::vector<std::wstring> candidates_; gy::english_candidates::CandidateSet english_candidate_set_; std::vector<unsigned> correction_indices_; std::wstring learned_phrase_pinyin_; std::wstring learned_phrase_text_; unsigned selected_ = 0; unsigned page_start_ = 0; bool chinese_grid_open_ = false; bool english_candidate_focus_ = false; bool english_list_open_ = false; bool english_assist_active_ = false; int input_mode_ = gy::input_mode::kSimplified; int chinese_mode_ = gy::input_mode::kSimplified; bool english_mode_ = false; bool input_scope_known_ = false; bool input_scope_direct_ = false; bool input_scope_sensitive_ = false; bool input_scope_manual_override_ = false; HWND input_scope_hwnd_ = nullptr; unsigned input_scope_probe_count_ = 0; bool last_commit_was_ascii_ = false; bool numeric_fragment_active_ = false; ExplicitLearn last_explicit_learn_{}; unsigned long long mode_generation_ = 0; unsigned long long candidate_input_generation_ = 0; bool single_quote_open_ = true; bool double_quote_open_ = true; bool shift_down_ = false; bool shift_used_ = false; bool control_down_ = false; bool alt_down_ = false; bool win_down_ = false;
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
  if (remove) {
    const LSTATUS result = RegDeleteTreeW(HKEY_LOCAL_MACHINE, key_name.c_str());
    TraceRegistration(L"RegDeleteTree", HRESULT_FROM_WIN32(result));
    return result == ERROR_SUCCESS || result == ERROR_FILE_NOT_FOUND ? S_OK : HRESULT_FROM_WIN32(result);
  }
  HKEY key = nullptr;
  const LSTATUS create_key = RegCreateKeyExW(HKEY_LOCAL_MACHINE, key_name.c_str(), 0, nullptr, 0,
                                             KEY_WRITE, nullptr, &key, nullptr);
  TraceRegistration(L"RegCreateKey CLSID", HRESULT_FROM_WIN32(create_key));
  if (create_key != ERROR_SUCCESS) return HRESULT_FROM_WIN32(create_key);
  const HRESULT title_hr = SetRegString(key, nullptr, L"GY 输入法文本服务");
  RegCloseKey(key);
  if (FAILED(title_hr)) return title_hr;
  HKEY server = nullptr;
  const LSTATUS create_server = RegCreateKeyExW(HKEY_LOCAL_MACHINE, (key_name + L"\\InprocServer32").c_str(),
                                                0, nullptr, 0, KEY_WRITE, nullptr, &server, nullptr);
  TraceRegistration(L"RegCreateKey Inproc", HRESULT_FROM_WIN32(create_server));
  if (create_server != ERROR_SUCCESS) return HRESULT_FROM_WIN32(create_server);
  wchar_t path[MAX_PATH]{};
  GetModuleFileNameW(g_module, path, MAX_PATH);
  const HRESULT path_hr = SetRegString(server, nullptr, path);
  const HRESULT model_hr = SetRegString(server, L"ThreadingModel", L"Apartment");
  RegCloseKey(server);
  return FAILED(path_hr) ? path_hr : model_hr;
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
    bool profile_already_registered = false;
    ITfInputProcessorProfiles* legacy_profiles = nullptr;
    if (SUCCEEDED(profiles->QueryInterface(IID_PPV_ARGS(&legacy_profiles))) && legacy_profiles) {
      IEnumTfLanguageProfiles* enumerator = nullptr;
      if (SUCCEEDED(legacy_profiles->EnumLanguageProfiles(kChinese, &enumerator)) && enumerator) {
        TF_LANGUAGEPROFILE profile{};
        ULONG fetched = 0;
        while (enumerator->Next(1, &profile, &fetched) == S_OK) {
          if (IsEqualGUID(profile.clsid, CLSID_GyTextService) &&
              IsEqualGUID(profile.guidProfile, GUID_PROFILE_GY_PINYIN)) {
            profile_already_registered = true;
            break;
          }
        }
        enumerator->Release();
      }
      legacy_profiles->Release();
    }

    // Preserve the current user's enabled GY language profile across upgrades.
    // UnregisterProfile is an uninstall operation: using it merely to refresh
    // metadata removes the TIP from the live language list and can leave the
    // user in Windows ENG after reboot. The stable shared icon/name do not need
    // per-version replacement, so an existing profile must remain untouched.
    if (profile_already_registered) {
      hr = S_OK;
    } else {
      wchar_t path[MAX_PATH]{}; GetModuleFileNameW(g_module, path, MAX_PATH);
      const std::wstring name = L"GY 输入法（拼音）";
      std::wstring icon_path = SharedIconPath();
      if (icon_path.empty() || GetFileAttributesW(icon_path.c_str()) == INVALID_FILE_ATTRIBUTES) {
        icon_path = ModuleDirectory() + L"\\gy.ico";
      }
      if (GetFileAttributesW(icon_path.c_str()) == INVALID_FILE_ATTRIBUTES) icon_path = path;
      hr = profiles->RegisterProfile(CLSID_GyTextService, kChinese, GUID_PROFILE_GY_PINYIN,
                                     name.c_str(), static_cast<ULONG>(name.size()), icon_path.c_str(),
                                     static_cast<ULONG>(icon_path.size()), 0, nullptr, 0, TRUE, 0);
    }
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
extern "C" HRESULT WINAPI DllRegisterServer() {
  const HRESULT init = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  const bool must_uninitialize = SUCCEEDED(init);
  TraceRegistration(L"CoInitializeEx", init);
  const HRESULT com_hr = RegisterComServer(false);
  TraceRegistration(L"RegisterComServer", com_hr);
  const HRESULT profile_hr = SUCCEEDED(com_hr) ? RegisterProfile(false) : com_hr;
  TraceRegistration(L"RegisterProfile", profile_hr);
  const HRESULT category_hr = SUCCEEDED(profile_hr) ? RegisterCategory(false) : profile_hr;
  TraceRegistration(L"RegisterCategory", category_hr);
  if (must_uninitialize) CoUninitialize();
  return FAILED(com_hr) ? com_hr : (FAILED(profile_hr) ? profile_hr : category_hr);
}
extern "C" HRESULT WINAPI DllUnregisterServer() {
  const HRESULT init = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  const bool must_uninitialize = SUCCEEDED(init);
  const HRESULT profile_hr = RegisterProfile(true);
  const HRESULT category_hr = RegisterCategory(true);
  const HRESULT com_hr = RegisterComServer(true);
  if (must_uninitialize) CoUninitialize();
  return FAILED(profile_hr) ? profile_hr : (FAILED(category_hr) ? category_hr : com_hr);
}



