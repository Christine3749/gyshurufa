package wang.shurufa.inputmethod.android

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.provider.Settings
import android.view.inputmethod.InputMethodManager
import android.widget.Button

/**
 * 首次启用引导页（T0，兼作系统设置入口）。
 *
 * 两步引导对应 Android IME 的标准链路：
 * 1. 跳转系统「管理输入法」页启用 GY；
 * 2. 弹出系统输入法选择器设为默认。
 * 厂商 ROM（小米/华为/OPPO/vivo）的拦截弹窗差异在 T8 真机矩阵逐台走查（契约 §11.5c）。
 */
class SetupActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_setup)

        findViewById<Button>(R.id.btn_enable_ime).setOnClickListener {
            startActivity(Intent(Settings.ACTION_INPUT_METHOD_SETTINGS))
        }
        findViewById<Button>(R.id.btn_set_default).setOnClickListener {
            getSystemService(InputMethodManager::class.java)?.showInputMethodPicker()
        }
    }
}
