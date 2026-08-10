package wang.shurufa.inputmethod.android

import android.inputmethodservice.InputMethodService
import android.view.View
import wang.shurufa.inputmethod.android.keyboard.KeyboardLayout
import wang.shurufa.inputmethod.android.keyboard.PlaceholderKeyboardView

/**
 * GY 输入法 Android 版 IME 服务（T0）。
 *
 * 身份受 android/identity.lock 契约锁保护：类名与包名改动 = 显式迁移。
 *
 * T0 职责边界：弹出自绘占位键盘、演示最小输入链路（字母直出/删除/回车）。
 * T1 起由 Rime 桥接层接管按键；T6 补模式机、inputType 识别与完整生命周期清理。
 */
class GyInputMethodService : InputMethodService() {

    private var keyboardView: PlaceholderKeyboardView? = null

    override fun onCreateInputView(): View {
        val view = PlaceholderKeyboardView(this).apply {
            onKey = ::handleKey
        }
        // 契约 §11.5b：全面屏手势区底部 inset（T0 简化实现，T6 换正式 WindowInsets 处理）。
        @Suppress("DEPRECATION")
        view.setOnApplyWindowInsetsListener { v, insets ->
            v.setPadding(0, 0, 0, insets.systemWindowInsetBottom)
            insets
        }
        keyboardView = view
        return view
    }

    /** 契约 §11.5a：禁用系统横屏全屏编辑模式（extract view），保护自绘视觉契约。 */
    override fun onEvaluateFullscreenMode(): Boolean = false

    private fun handleKey(label: String) {
        val inputConnection = currentInputConnection ?: return
        when (label) {
            KeyboardLayout.KEY_BACKSPACE -> inputConnection.deleteSurroundingText(1, 0)
            KeyboardLayout.KEY_ENTER -> sendKeyChar('\n')
            KeyboardLayout.KEY_SHIFT, KeyboardLayout.KEY_MODE_SWITCH -> Unit // T6 模式机接管
            else -> inputConnection.commitText(label, 1)
        }
    }

    override fun onDestroy() {
        // 契约 §11.3：视图回调持有服务引用，销毁时显式断开，避免悬挂到已销毁实例。
        keyboardView?.onKey = null
        keyboardView = null
        super.onDestroy()
    }
}
