package wang.shurufa.inputmethod.android

import android.inputmethodservice.InputMethodService
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * T0 真机冒烟：服务可被系统绑定链发现的最小契约。
 * 完整的「启用 → 设为默认 → 弹出键盘」链路在 T8 真机矩阵人工验收（厂商弹窗不可自动化）。
 */
@RunWith(AndroidJUnit4::class)
class GyInputMethodServiceSmokeTest {

    @Test
    fun targetPackageMatchesIdentityLock() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        assertEquals("wang.shurufa.inputmethod.GYInputAndroid", context.packageName)
    }

    @Test
    fun serviceIsAnInputMethodService() {
        assertTrue(InputMethodService::class.java.isAssignableFrom(GyInputMethodService::class.java))
    }
}
