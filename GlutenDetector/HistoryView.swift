//
//  HistoryView.swift
//  GlutenDetector
//
//  Scan history saved on the device with SwiftData (FR9).
//  Nothing leaves the phone (NFR7).
//

import SwiftUI
import SwiftData

/// One saved scan. SwiftData stores these automatically.
@Model
final class ScanRecord {
    var date: Date
    var resultRaw: String          // GlutenResult.rawValue
    var reason: String             // English sentence (fallback for old records)
    var reasonCode: String = ""    // lets the reason be shown in either language
    var reasonTerms: String = ""
    var extractedText: String
    @Attribute(.externalStorage) var thumbnail: Data?   // small JPEG of the label

    init(date: Date = .now,
         result: GlutenResult,
         reason: AnalysisReason,
         extractedText: String,
         thumbnail: Data?) {
        self.date = date
        self.resultRaw = result.rawValue
        self.reason = reason.text(.english)
        self.reasonCode = reason.code
        self.reasonTerms = reason.terms
        self.extractedText = extractedText
        self.thumbnail = thumbnail
    }

    var result: GlutenResult { GlutenResult(rawValue: resultRaw) ?? .uncertain }

    func reasonText(_ lang: AppLanguage) -> String {
        if let r = AnalysisReason(code: reasonCode, terms: reasonTerms) { return r.text(lang) }
        return reason
    }
}

private let historyDateFormat = Date.FormatStyle()
    .year().month(.abbreviated).day().hour().minute()

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appLanguage) private var lang
    // Newest first. The list updates by itself whenever a scan is saved/deleted.
    @Query(sort: \ScanRecord.date, order: .reverse) private var scans: [ScanRecord]

    var body: some View {
        Group {
            if scans.isEmpty {
                ContentUnavailableView(
                    lang.t(.noScansYet),
                    systemImage: "clock.arrow.circlepath",
                    description: Text(lang.t(.noScansDesc))
                )
            } else {
                List {
                    ForEach(scans) { scan in
                        NavigationLink {
                            ScanDetailView(scan: scan)
                        } label: {
                            row(for: scan)
                        }
                    }
                    .onDelete(perform: delete)
                }
            }
        }
        .navigationTitle(lang.t(.history))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !scans.isEmpty { EditButton() }
        }
        .background(AppColor.background.ignoresSafeArea())
    }

    private func row(for scan: ScanRecord) -> some View {
        HStack(spacing: 12) {
            if let data = scan.thumbnail, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            VStack(alignment: .leading, spacing: 2) {
                Label(scan.result.title(lang), systemImage: scan.result.icon)
                    .font(.headline)
                    .foregroundColor(scan.result.color)
                Text(scan.date, format: historyDateFormat)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(scans[index])
        }
        try? modelContext.save()
    }
}

/// Tap a history row to see the full saved result.
struct ScanDetailView: View {
    let scan: ScanRecord
    @Environment(\.appLanguage) private var lang

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let data = scan.thumbnail, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }

                Image(systemName: scan.result.icon)
                    .font(.system(size: 48))
                    .foregroundColor(scan.result.color)

                Text(scan.result.title(lang))
                    .font(.title2.bold())
                    .foregroundColor(scan.result.color)

                Text(scan.reasonText(lang))
                    .font(.subheadline)
                    .multilineTextAlignment(.center)

                Text(scan.date, format: historyDateFormat)
                    .font(.caption)
                    .foregroundColor(.secondary)

                GroupBox(lang.t(.extractedText)) {
                    Text(scan.extractedText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
            .padding()
        }
        .navigationTitle(lang.t(.scan))
        .navigationBarTitleDisplayMode(.inline)
        .background(AppColor.background.ignoresSafeArea())
    }
}

#Preview {
    NavigationStack {
        HistoryView()
    }
    .modelContainer(for: ScanRecord.self, inMemory: true)
}
