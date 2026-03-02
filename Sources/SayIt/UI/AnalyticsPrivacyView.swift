import SwiftUI

struct AnalyticsPrivacyView: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Data Privacy")
                        .font(.system(size: 18, weight: .semibold))
                    Text("Analytics and external telemetry status")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Done") { self.dismiss() }
                    .buttonStyle(.bordered)
            }

            Divider().opacity(0.4)

            Text("匿名上报已禁用")
                .font(.system(size: 13))
                .foregroundStyle(self.theme.palette.secondaryText)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(self.theme.palette.contentBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(self.theme.palette.cardBorder.opacity(0.6), lineWidth: 1)
                )

            Divider().opacity(0.4)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    self.sectionTitle("本地说明")
                    self.bullet("应用不会向外部服务器上传转录文本、音频或输入内容。")
                    self.bullet("不会主动发送会话、热键或模型运行日志。")
                    self.bullet("所有操作数据保留在本地，按你的系统设置控制。")
                }
                .padding(.vertical, 6)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(self.theme.palette.contentBackground)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(self.theme.palette.accent)
            .padding(.top, 4)
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .foregroundStyle(.secondary)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
    }
}
