package wang.shurufa.inputmethod.android.keyboard

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 键位表的结构约束：视图层信任本表渲染，表的错误会直接变成 UI 缺陷。
 * T3 扩展键位表（角标/变体/权重）时先改这里。
 */
class KeyboardLayoutTest {

    @Test
    fun `has four rows`() {
        assertEquals(4, KeyboardLayout.rows.size)
    }

    @Test
    fun `covers all 26 letters exactly once`() {
        val letters = KeyboardLayout.letterLabels
        assertEquals(26, letters.size)
        for (c in 'a'..'z') {
            assertTrue("missing letter $c", c.toString() in letters)
        }
    }

    @Test
    fun `functional keys present in expected rows`() {
        val thirdRow = KeyboardLayout.rows[2].map { it.label }
        val fourthRow = KeyboardLayout.rows[3].map { it.label }
        assertTrue(KeyboardLayout.KEY_SHIFT in thirdRow)
        assertTrue(KeyboardLayout.KEY_BACKSPACE in thirdRow)
        assertTrue(KeyboardLayout.KEY_MODE_SWITCH in fourthRow)
        assertTrue(KeyboardLayout.KEY_ENTER in fourthRow)
        assertTrue(KeyboardLayout.KEY_SPACE in fourthRow)
    }

    @Test
    fun `all key weights are positive`() {
        KeyboardLayout.rows.flatten().forEach { key ->
            assertTrue(key.weight > 0f)
        }
    }
}
