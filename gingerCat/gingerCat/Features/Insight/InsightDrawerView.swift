import SwiftUI

struct InsightDrawerView: View {
    @Environment(\.dismiss) private var dismiss

    let payload: InsightPayload
    let onSave: (ScanRecord) -> Void

    @State private var selectedEventIDs: Set<UUID> = []
    @State private var note = ""

    var body: some View {
        NavigationStack {
            ZStack {
                LiquidBackground()

                ScrollView {
                    if #available(iOS 26, *) {
                        GlassEffectContainer(spacing: 14) {
                            insightSections
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 20)
                    } else {
                        insightSections
                            .padding(.horizontal, 16)
                            .padding(.vertical, 20)
                    }
                }
            }
            .navigationTitle(String(localized: "结果分析"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "关闭"), action: dismiss.callAsFunction)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "保存到历史"), action: saveRecord)
                        .fontWeight(.semibold)
                }
            }
        }
        .onAppear {
            selectedEventIDs = Set(payload.events.map(\.id))
        }
    }

    private var insightSections: some View {
        VStack(alignment: .leading, spacing: 14) {
            summaryCard
            gatekeeperCard
            noteCard
        }
    }

    private var summaryCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(
                        payload.summarySource == .ai ? String(localized: "AI 摘要") : String(localized: "识别文本"),
                        systemImage: payload.summarySource == .ai ? "sparkles.rectangle.stack" : "text.quote"
                    )
                    .font(.headline)

                    Spacer(minLength: 0)

                    Text(payload.summarySource == .ai ? String(localized: "Kimi") : String(localized: "OCR"))
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AppTheme.primary.opacity(0.16), in: Capsule())
                }

                Text(payload.summary)
                    .font(.body)

                Divider()

                Text(payload.rawText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }
        }
    }

    private var gatekeeperCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(String(localized: "意图判定"), systemImage: "shield.checkered")
                        .font(.headline)

                    Spacer()

                    Text(payload.mode == .schedule ? String(localized: "日程模式") : String(localized: "总结模式"))
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(AppTheme.primary.opacity(0.18), in: Capsule())
                }

                if payload.mode == .schedule, !payload.events.isEmpty {
                    ForEach(payload.events) { event in
                        EventSelectionRow(event: event, isSelected: binding(for: event))
                    }

                    if #available(iOS 26, *) {
                        Button {
                            // Placeholder: future CalendarManager integration.
                        } label: {
                            Label(String(localized: "写入日历（预留）"), systemImage: "calendar.badge.plus")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glassProminent)
                        .disabled(true)
                    } else {
                        Button {
                            // Placeholder: future CalendarManager integration.
                        } label: {
                            Label(String(localized: "写入日历（预留）"), systemImage: "calendar.badge.plus")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.primary)
                        .disabled(true)
                    }
                } else {
                    Text(String(localized: "当前内容未识别到完整时间信息，已自动隐藏写入日历能力。"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var noteCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Label(String(localized: "备注"), systemImage: "text.bubble")
                    .font(.headline)

                TextField(String(localized: "添加备注（可选）"), text: $note, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private func binding(for event: InsightEvent) -> Binding<Bool> {
        Binding(
            get: {
                selectedEventIDs.contains(event.id)
            },
            set: { isSelected in
                if isSelected {
                    selectedEventIDs.insert(event.id)
                } else {
                    selectedEventIDs.remove(event.id)
                }
            }
        )
    }

    private func saveRecord() {
        let selectedEvent = payload.events.first(where: { selectedEventIDs.contains($0.id) })

        let record = ScanRecord(
            imageData: payload.imageData,
            source: payload.source,
            recognizedText: payload.rawText,
            summary: payload.summary,
            intent: payload.mode.intent,
            eventTitle: selectedEvent?.title,
            eventDate: selectedEvent?.date,
            note: note
        )

        onSave(record)
        dismiss()
    }
}

private struct EventSelectionRow: View {
    let event: InsightEvent
    @Binding var isSelected: Bool

    var body: some View {
        Button {
            isSelected.toggle()
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? AppTheme.primary : .secondary)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    Text(event.title)
                        .font(.subheadline.weight(.medium))

                    Text(AppDateTimeFormatter.string(from: event.date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    InsightDrawerView(
        payload: InsightPayloadBuilder.build(
            source: "Photo",
            recognizedText: "4月9日 10:00 迭代评审会\n4月11日 19:30 电影首映抢票"
        )
    ) { _ in }
}
