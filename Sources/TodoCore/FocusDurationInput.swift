import Foundation

/// 输入草稿只在提交时转换；非法值不静默截断，也不替换已保存时长。
public enum FocusDurationInput {
    public static func minutes(from text: String, in range: ClosedRange<Int>) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.utf8.allSatisfy({ (48...57).contains($0) }),
              let value = Int(trimmed), range.contains(value) else { return nil }
        return value
    }
}
