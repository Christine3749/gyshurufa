package wang.shurufa.inputmethod.android.keyboard

/**
 * 键位表驱动的键盘布局数据（T0 占位版：字母区四行 + 功能区）。
 *
 * 设计契约 §二工程基线：布局由数据描述、不依赖 Android 框架，
 * T3 将在此扩展上滑角标、长按变体、功能键权重与三档高度——
 * 视图层（PlaceholderKeyboardView → KeyboardView）只消费本表，不写死坐标。
 */
object KeyboardLayout {

    /** 按键定义。[weight] 为行内宽度权重（1f = 标准字母键宽）。 */
    data class Key(val label: String, val weight: Float = 1f) {
        init {
            require(label.isNotEmpty()) { "key label must not be empty" }
            require(weight > 0f) { "key weight must be positive: $label" }
        }
    }

    /** 功能键标签（与 GyInputMethodService 的分发约定一一对应）。 */
    const val KEY_SHIFT = "⇧"
    const val KEY_BACKSPACE = "⌫"
    const val KEY_MODE_SWITCH = "中/EN"
    const val KEY_ENTER = "↵"
    const val KEY_SPACE = " "

    val rows: List<List<Key>> = listOf(
        listOf("q", "w", "e", "r", "t", "y", "u", "i", "o", "p").map(::Key),
        listOf("a", "s", "d", "f", "g", "h", "j", "k", "l").map(::Key),
        listOf(Key(KEY_SHIFT, 1.5f)) +
            listOf("z", "x", "c", "v", "b", "n", "m").map(::Key) +
            listOf(Key(KEY_BACKSPACE, 1.5f)),
        listOf(
            Key(KEY_MODE_SWITCH, 1.5f),
            Key(",", 1f),
            Key(KEY_SPACE, 5f),
            Key(".", 1f),
            Key(KEY_ENTER, 1.5f),
        ),
    )

    /** 全部单字符字母键（触摸上屏的最小输入路径，T0 冒烟用）。 */
    val letterLabels: Set<String>
        get() = rows.flatten().map { it.label }.filterTo(HashSet()) { it.length == 1 && it[0] in 'a'..'z' }
}
