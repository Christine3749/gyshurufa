package wang.shurufa.inputmethod.core.candidate

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Test

class CandidateGovernanceTest {
    @Test
    fun `maps filtered display indices to absolute engine indices`() {
        val snapshot = CandidateGovernance.build(
            listOf(
                raw(0, "🙂"),
                raw(1, "你好"),
                raw(2, "祢蚝"),
                raw(3, "你好"),
                raw(4, "妮恏"),
            ),
        )

        assertEquals(listOf("你好", "祢蚝", "妮恏"), snapshot.texts)
        assertEquals(1, snapshot.selectionAt(0)?.engineIndex)
        assertEquals(2, snapshot.selectionAt(1)?.engineIndex)
        assertEquals(4, snapshot.selectionAt(2)?.engineIndex)
    }

    @Test
    fun `mac 祢蚝 regression keeps the first visible selection on the correct engine candidate`() {
        val snapshot = CandidateGovernance.build(
            listOf(
                raw(40, "😀"),
                raw(41, "你好"),
                raw(42, "祢蚝"),
                raw(43, "妮恏"),
            ),
        )

        val firstSelection = snapshot.selectionAt(0)

        assertEquals("你好", snapshot.texts.first())
        assertEquals(41, firstSelection?.engineIndex)
    }

    @Test
    fun `filters non CJK emoji symbols private-use characters and overlong candidates`() {
        val snapshot = CandidateGovernance.build(
            listOf(
                raw(0, "你好"),
                raw(1, "你好！"),
                raw(2, "A"),
                raw(3, "你 好"),
                raw(4, "你\uE000好"),
                raw(5, "😀"),
                raw(6, "一".repeat(13)),
                raw(7, ""),
            ),
        )

        assertEquals(listOf("你好"), snapshot.texts)
    }

    @Test
    fun `accepts the same BMP CJK ranges as desktop and rejects supplementary characters`() {
        val snapshot = CandidateGovernance.build(
            listOf(
                raw(0, "㐀"),
                raw(1, "一".repeat(12)),
                raw(2, "豈"),
                raw(3, "𠀀"),
            ),
        )

        assertEquals(listOf("㐀", "一".repeat(12), "豈"), snapshot.texts)
    }

    @Test
    fun `deduplicates by text and keeps the first engine index`() {
        val snapshot = CandidateGovernance.build(
            listOf(
                raw(3, "中国"),
                raw(8, "中国"),
                raw(12, "中文"),
            ),
        )

        assertEquals(listOf("中国", "中文"), snapshot.texts)
        assertEquals(3, snapshot.selectionAt(0)?.engineIndex)
        assertEquals(12, snapshot.selectionAt(1)?.engineIndex)
    }

    @Test
    fun `caps the pool at 75 and does not expose invalid display selections`() {
        val snapshot = CandidateGovernance.build(
            (0..MAX_RAW_INDEX).map { raw(it, String(Character.toChars(0x4E00 + it))) },
        )

        assertEquals(CandidateGovernance.MAX_CANDIDATE_POOL_SIZE, snapshot.size)
        assertEquals(74, snapshot.selectionAt(74)?.engineIndex)
        assertNull(snapshot.selectionAt(-1))
        assertNull(snapshot.selectionAt(CandidateGovernance.MAX_CANDIDATE_POOL_SIZE))
    }

    @Test
    fun `rejects malformed engine indexes before a mapping can be created`() {
        assertThrows(IllegalArgumentException::class.java) { raw(-1, "你好") }
    }

    @Test
    fun `fails closed when an engine response repeats an absolute index`() {
        assertThrows(IllegalStateException::class.java) {
            CandidateGovernance.build(listOf(raw(4, "你好"), raw(4, "世界")))
        }
    }

    private fun raw(engineIndex: Int, text: String) = RawEngineCandidate(engineIndex, text)

    private companion object {
        const val MAX_RAW_INDEX = CandidateGovernance.MAX_CANDIDATE_POOL_SIZE
    }
}
