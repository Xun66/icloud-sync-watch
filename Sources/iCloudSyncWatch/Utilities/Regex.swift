import Foundation

struct Regex {
    private let expression: NSRegularExpression

    init(_ pattern: String) {
        self.expression = try! NSRegularExpression(pattern: pattern, options: [])
    }

    func firstMatch(in input: String) -> [String]? {
        let range = NSRange(input.startIndex..<input.endIndex, in: input)
        guard let match = expression.firstMatch(in: input, options: [], range: range) else {
            return nil
        }

        return (1..<match.numberOfRanges).compactMap { index in
            let capture = match.range(at: index)
            guard capture.location != NSNotFound, let swiftRange = Range(capture, in: input) else {
                return nil
            }
            return String(input[swiftRange])
        }
    }

    func allMatches(in input: String) -> [[String]] {
        let range = NSRange(input.startIndex..<input.endIndex, in: input)
        return expression.matches(in: input, options: [], range: range).map { match in
            (1..<match.numberOfRanges).compactMap { index in
                let capture = match.range(at: index)
                guard capture.location != NSNotFound, let swiftRange = Range(capture, in: input) else {
                    return nil
                }
                return String(input[swiftRange])
            }
        }
    }
}
