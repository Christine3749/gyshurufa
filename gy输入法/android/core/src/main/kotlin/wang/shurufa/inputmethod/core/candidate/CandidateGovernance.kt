package wang.shurufa.inputmethod.core.candidate

/**
 * A candidate as supplied by the engine. [engineIndex] is its absolute index
 * across the current Rime candidate window, rather than a page-local index.
 */
data class RawEngineCandidate(
    val engineIndex: Int,
    val text: String,
) {
    init {
        require(engineIndex >= 0) { "engineIndex must be an absolute non-negative index" }
    }
}

/**
 * An opaque selection token. UI code must obtain it from [CandidateSnapshot]
 * and pass it unchanged to the engine bridge; it must never recreate an engine
 * index from the displayed row number.
 */
class CandidateSelection internal constructor(
    val engineIndex: Int,
)

/**
 * Immutable, governed candidate state for one engine composition.
 *
 * The display list and the engine-index map are built atomically. This is the
 * guard against the historic filtered-candidate selection mismatch: the UI may
 * select display index 0, while the engine must receive a later raw index.
 */
class CandidateSnapshot internal constructor(
    private val accepted: List<AcceptedCandidate>,
) {
    val texts: List<String> = accepted.map(AcceptedCandidate::text)

    val size: Int
        get() = accepted.size

    fun selectionAt(displayIndex: Int): CandidateSelection? =
        accepted.getOrNull(displayIndex)?.let { CandidateSelection(it.engineIndex) }

    internal data class AcceptedCandidate(
        val engineIndex: Int,
        val text: String,
    )
}

/**
 * Shared governance for candidates shown by GY clients.
 *
 * This intentionally mirrors the desktop quality gate: BMP CJK ideographs in
 * Extension A, Unified Ideographs, or Compatibility Ideographs only; an exact
 * maximum of 12 UTF-16 code units; first occurrence wins; and at most 75
 * visible candidates. There are no Android framework dependencies here.
 */
object CandidateGovernance {
    const val MAX_CANDIDATE_LENGTH = 12
    const val MAX_CANDIDATE_POOL_SIZE = 75

    fun build(rawCandidates: Iterable<RawEngineCandidate>): CandidateSnapshot {
        val accepted = ArrayList<CandidateSnapshot.AcceptedCandidate>(MAX_CANDIDATE_POOL_SIZE)
        val seenTexts = HashSet<String>()
        val seenEngineIndexes = HashSet<Int>()

        for (candidate in rawCandidates) {
            if (accepted.size == MAX_CANDIDATE_POOL_SIZE) break
            check(seenEngineIndexes.add(candidate.engineIndex)) {
                "engine emitted duplicate absolute candidate index ${candidate.engineIndex}"
            }
            if (!isQualityCandidate(candidate.text) || !seenTexts.add(candidate.text)) continue
            accepted += CandidateSnapshot.AcceptedCandidate(candidate.engineIndex, candidate.text)
        }

        return CandidateSnapshot(accepted)
    }

    private fun isQualityCandidate(text: String): Boolean {
        if (text.isEmpty() || text.length > MAX_CANDIDATE_LENGTH) return false

        var offset = 0
        while (offset < text.length) {
            val codePoint = Character.codePointAt(text, offset)
            if (!isDesktopSupportedCjkIdeograph(codePoint)) return false
            offset += Character.charCount(codePoint)
        }
        return true
    }

    private fun isDesktopSupportedCjkIdeograph(codePoint: Int): Boolean =
        codePoint in CJK_EXTENSION_A_RANGE ||
            codePoint in CJK_UNIFIED_RANGE ||
            codePoint in CJK_COMPATIBILITY_RANGE

    private val CJK_EXTENSION_A_RANGE = 0x3400..0x4DBF
    private val CJK_UNIFIED_RANGE = 0x4E00..0x9FFF
    private val CJK_COMPATIBILITY_RANGE = 0xF900..0xFAFF
}
