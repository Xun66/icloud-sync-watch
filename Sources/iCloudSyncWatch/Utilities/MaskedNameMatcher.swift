import Foundation

enum MaskedNameMatcher {
    static func matches(maskedName: String, candidate: String) -> Bool {
        let maskedScalars = Array(maskedName.unicodeScalars)
        let candidateScalars = Array(candidate.unicodeScalars)

        var maskedIndex = 0
        var candidateIndex = 0

        while maskedIndex < maskedScalars.count {
            if maskedScalars[maskedIndex] == "{",
               let wildcard = parseWildcard(in: maskedScalars, at: maskedIndex)
            {
                candidateIndex += wildcard.count
                maskedIndex = wildcard.nextIndex
                if candidateIndex > candidateScalars.count {
                    return false
                }
                continue
            }

            guard candidateIndex < candidateScalars.count else {
                return false
            }
            guard maskedScalars[maskedIndex] == candidateScalars[candidateIndex] else {
                return false
            }

            maskedIndex += 1
            candidateIndex += 1
        }

        return candidateIndex == candidateScalars.count
    }

    private static func parseWildcard(
        in scalars: [Unicode.Scalar],
        at index: Int
    ) -> (count: Int, nextIndex: Int)? {
        var digits = ""
        var cursor = index + 1

        while cursor < scalars.count, scalars[cursor] != "}" {
            digits.unicodeScalars.append(scalars[cursor])
            cursor += 1
        }

        guard cursor < scalars.count, scalars[cursor] == "}", let value = Int(digits) else {
            return nil
        }

        return (count: value, nextIndex: cursor + 1)
    }
}
