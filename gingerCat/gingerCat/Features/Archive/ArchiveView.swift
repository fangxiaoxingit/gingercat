import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

struct ArchiveView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ScanRecord.createdAt, order: .reverse) private var records: [ScanRecord]

    @State private var searchText = ""
    @State private var selectedRecord: ScanRecord?

    var body: some View {
        ZStack {
            LiquidBackground()

            if filteredRecords.isEmpty {
                emptyStateView
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .padding(.horizontal, 24)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(filteredRecords.enumerated()), id: \.element.id) { index, record in
                            Button {
                                selectedRecord = record
                            } label: {
                                ArchiveRow(record: record)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .background(
                                index == filteredRecords.count - 1 ? Color.clear : Color.black.opacity(0.06)
                                    .frame(height: 0.5)
                                    .frame(maxHeight: .infinity, alignment: .bottom)
