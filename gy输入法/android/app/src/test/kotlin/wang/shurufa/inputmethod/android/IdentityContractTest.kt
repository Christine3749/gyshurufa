package wang.shurufa.inputmethod.android

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import wang.shurufa.inputmethod.android.keyboard.KeyboardLayout

/**
 * 身份契约的代码侧守卫：与 android/identity.lock、verify_identity.py 构成三保险。
 * 任何身份字段漂移必须三处同时显式变更——这正是契约锁的目的。
 */
class IdentityContractTest {

    @Test
    fun `applicationId matches identity lock`() {
        assertEquals("wang.shurufa.inputmethod.GYInputAndroid", BuildConfig.APPLICATION_ID)
    }

    @Test
    fun `code package matches namespace lock`() {
        assertTrue(
            GyInputMethodService::class.java.name.startsWith("wang.shurufa.inputmethod.android."),
        )
    }
}
