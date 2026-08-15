package wang.shurufa.inputmethod.android.keyboard

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.view.MotionEvent
import android.view.View

/**
 * T0 占位键盘：自绘卡片式按键 + 按压态，验证「键位表驱动 + 自绘 View」的最小链路。
 *
 * 已知边界（T3 替换为正式 KeyboardView 时全部接管）：
 * - 无字符气泡、无上滑角标、无长按变体、无滑动删除（契约 §三，T4 手势族）
 * - 单指触控；颜色暂用简化色板，主题表 T3 接入（契约 §3.8 不写死）
 * - 空格键上的模式标（中/EN）为静态文本，模式机 T6 接入
 */
class PlaceholderKeyboardView(context: Context) : View(context) {

    /** 按键回调。服务层据此分发 commit/delete/功能键；T6 起经模式机裁决。 */
    var onKey: ((String) -> Unit)? = null

    private data class KeyRect(val key: KeyboardLayout.Key, val rect: RectF)

    private val keyRects = mutableListOf<KeyRect>()
    private var pressedKey: KeyboardLayout.Key? = null

    private val keyPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = COLOR_KEY_TEXT
        textAlign = Paint.Align.CENTER
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val width = MeasureSpec.getSize(widthMeasureSpec)
        setMeasuredDimension(width, resolveSize(desiredHeight(), heightMeasureSpec))
    }

    private fun desiredHeight(): Int {
        val density = resources.displayMetrics.density
        val rows = KeyboardLayout.rows.size
        val v = KEY_VERTICAL_GAP_DP * (rows + 1) + KEY_HEIGHT_DP * rows
        return (v * density).toInt()
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        layoutKeys(w, h)
    }

    private fun layoutKeys(width: Int, height: Int) {
        keyRects.clear()
        val density = resources.displayMetrics.density
        val vGap = KEY_VERTICAL_GAP_DP * density
        val hGap = KEY_HORIZONTAL_GAP_DP * density
        val rows = KeyboardLayout.rows
        val keyHeight = (height - paddingBottom - vGap * (rows.size + 1)) / rows.size

        var top = vGap
        for (row in rows) {
            val totalWeight = row.sumOf { it.weight.toDouble() }.toFloat()
            val available = width - hGap * (row.size + 1)
            var left = hGap
            for (key in row) {
                val keyWidth = available * (key.weight / totalWeight)
                keyRects += KeyRect(key, RectF(left, top, left + keyWidth, top + keyHeight))
                left += keyWidth + hGap
            }
            top += keyHeight + vGap
        }
    }

    override fun onDraw(canvas: Canvas) {
        canvas.drawColor(COLOR_KEYBOARD_BG)
        val density = resources.displayMetrics.density
        textPaint.textSize = KEY_TEXT_SIZE_SP * resources.displayMetrics.scaledDensity
        val corner = KEY_CORNER_DP * density

        for ((key, rect) in keyRects) {
            keyPaint.color = if (key == pressedKey) COLOR_KEY_PRESSED else COLOR_KEY_NORMAL
            canvas.drawRoundRect(rect, corner, corner, keyPaint)

            val label = if (key.label == KeyboardLayout.KEY_SPACE) KeyboardLayout.KEY_MODE_SWITCH else key.label
            val baseline = rect.centerY() - (textPaint.descent() + textPaint.ascent()) / 2
            canvas.drawText(label, rect.centerX(), baseline, textPaint)
        }
    }

    @SuppressLint("ClickableViewAccessibility")
    override fun onTouchEvent(event: MotionEvent): Boolean {
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                pressedKey = keyAt(event.x, event.y)
                invalidate()
                return true
            }
            MotionEvent.ACTION_MOVE -> {
                val hit = keyAt(event.x, event.y)
                if (hit != pressedKey) {
                    pressedKey = hit
                    invalidate()
                }
                return true
            }
            MotionEvent.ACTION_UP -> {
                val released = keyAt(event.x, event.y)
                if (released != null && released == pressedKey) {
                    onKey?.invoke(released.label)
                }
                pressedKey = null
                invalidate()
                return true
            }
            MotionEvent.ACTION_CANCEL -> {
                pressedKey = null
                invalidate()
                return true
            }
        }
        return super.onTouchEvent(event)
    }

    private fun keyAt(x: Float, y: Float): KeyboardLayout.Key? =
        keyRects.firstOrNull { it.rect.contains(x, y) }?.key

    private companion object {
        const val KEY_HEIGHT_DP = 52f
        const val KEY_VERTICAL_GAP_DP = 8f
        const val KEY_HORIZONTAL_GAP_DP = 6f
        const val KEY_CORNER_DP = 6f
        const val KEY_TEXT_SIZE_SP = 20f

        // T0 简化色板（浅色）。正式主题表（浅/深/跟随系统）由 T3 按 VI 令牌接入。
        val COLOR_KEYBOARD_BG = Color.rgb(0xD1, 0xD5, 0xDB)
        val COLOR_KEY_NORMAL = Color.WHITE
        val COLOR_KEY_PRESSED = Color.rgb(0xAE, 0xB4, 0xBF)
        val COLOR_KEY_TEXT = Color.rgb(0x11, 0x13, 0x18)
    }
}
