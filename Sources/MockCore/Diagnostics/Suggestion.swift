/// Produces "did you mean …?" suggestions for likely typos in user input.
///
/// Protocol extensions use this to attach fix-it hints to their diagnostics — unknown type
/// names, misspelled fields, near-miss enum members, and the like.
public struct Suggestion {
    /// Returns the candidate closest to `input`, if any candidate is close enough to plausibly
    /// be what the author meant.
    ///
    /// The result does not depend on the order of `candidates`: equally close candidates are
    /// resolved alphabetically. Callers routinely pass `Dictionary.keys`, whose order changes
    /// from run to run, and an error message that names a different fix each time it is
    /// printed cannot be asserted in a test or trusted in a log.
    public static func nearest(to input: String, in candidates: some Collection<String>) -> String? {
        var best: (candidate: String, distance: Int)?
        // Only suggest when the edit distance is small relative to the input length; a
        // suggestion that shares almost nothing with the input is noise, not help.
        let threshold = max(1, input.count / 3)
        let loweredInput = input.lowercased()
        for candidate in candidates where candidate != input {
            // Case-only mismatches are overwhelmingly likely to be the intended fix, so they
            // rank ahead of every real edit.
            let distance =
                candidate.lowercased() == loweredInput ? 0 : editDistance(input, candidate, limit: threshold)
            guard distance <= threshold else { continue }
            if let current = best, (current.distance, current.candidate) <= (distance, candidate) {
                continue
            }
            best = (candidate, distance)
        }
        return best?.candidate
    }

    /// Formats a suggestion clause for appending to an error message, or an empty string when
    /// there is nothing worth suggesting.
    public static func clause(for input: String, in candidates: some Collection<String>) -> String {
        guard let match = nearest(to: input, in: candidates) else { return "" }
        return " Did you mean '\(match)'?"
    }

    /// Transposition-aware (optimal string alignment) edit distance, abandoning early once the
    /// distance is known to exceed `limit`. Transpositions count as one edit because swapped
    /// letters ("tpye" for "type") are among the most common typos.
    private static func editDistance(_ lhs: String, _ rhs: String, limit: Int) -> Int {
        let lhsChars = Array(lhs)
        let rhsChars = Array(rhs)
        if abs(lhsChars.count - rhsChars.count) > limit {
            return limit + 1
        }
        var twoRowsBack = [Int](repeating: 0, count: rhsChars.count + 1)
        var previousRow = Array(0...rhsChars.count)
        var currentRow = [Int](repeating: 0, count: rhsChars.count + 1)
        for (lhsIndex, lhsChar) in lhsChars.enumerated() {
            currentRow[0] = lhsIndex + 1
            var rowMinimum = currentRow[0]
            for (rhsIndex, rhsChar) in rhsChars.enumerated() {
                let substitution = previousRow[rhsIndex] + (lhsChar == rhsChar ? 0 : 1)
                let insertion = currentRow[rhsIndex] + 1
                let deletion = previousRow[rhsIndex + 1] + 1
                var cost = min(substitution, insertion, deletion)
                if lhsIndex > 0, rhsIndex > 0,
                    lhsChar == rhsChars[rhsIndex - 1], lhsChars[lhsIndex - 1] == rhsChar
                {
                    cost = min(cost, twoRowsBack[rhsIndex - 1] + 1)
                }
                currentRow[rhsIndex + 1] = cost
                rowMinimum = min(rowMinimum, cost)
            }
            if rowMinimum > limit {
                return limit + 1
            }
            (twoRowsBack, previousRow, currentRow) = (previousRow, currentRow, twoRowsBack)
        }
        return previousRow[rhsChars.count]
    }
}
