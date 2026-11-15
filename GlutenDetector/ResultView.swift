//
//  ResultView.swift
//  GlutenDetector
//
//  Runs OCR on the photo from Home, analyses the text (English + Arabic),
//  shows the verdict with matched ingredients highlighted, and saves the scan.
//

import SwiftUI
import SwiftData

enum GlutenResult: String {   // String raw values let SwiftData store it
    case containsGluten
    case noGlutenDetected
    case uncertain

    func title(_ lang: AppLanguage) -> String {
        switch self {
        case .containsGluten: return lang.t(.containsGluten)
        case .noGlutenDetected: return lang.t(.noGlutenDetected)
        case .uncertain: return lang.t(.uncertain)
        }
    }

    var color: Color {
        switch self {
        case .containsGluten: return AppColor.danger
        case .noGlutenDetected: return AppColor.safe
        case .uncertain: return AppColor.warning
        }
    }

    var icon: String {
        switch self {
        case .containsGluten: return "xmark.octagon.fill"
        case .noGlutenDetected: return "checkmark.seal.fill"
        case .uncertain: return "questionmark.diamond.fill"
        }
    }
}

struct ResultView: View {
    // The photo passed in from Home. Optional so previews/tests still work.
    var capturedImage: UIImage?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appLanguage) private var lang

    @State private var didSave = false   // makes sure one scan = one history entry
    @State private var isAnalyzing = true
    @State private var extractedText = ""
    @State private var analysis: GlutenAnalysis?
    @State private var errorMessage: String?
    @State private var arabicUnavailable = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {

                if let capturedImage {
                    Image(uiImage: capturedImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal)
                }

                if isAnalyzing {
                    ProgressView(lang.t(.readingLabel))
                        .padding(.vertical, 40)
                } else if let errorMessage {
                    errorSection(errorMessage)
                } else if let analysis {
                    resultSection(analysis)
                }

                Text(lang.t(.disclaimer))
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Button(lang.t(.scanAgain)) {
                    dismiss()   // pops back to Home
                }
                .primaryButton()
                .padding(.horizontal)
            }
            .padding(.top, 24)
            .padding(.bottom, 24)
        }
        .navigationTitle(lang.t(.result))
        .navigationBarTitleDisplayMode(.inline)
        .background(AppColor.background.ignoresSafeArea())
        .task { await runAnalysis() }
    }

    // MARK: - Sections

    @ViewBuilder
    private func resultSection(_ analysis: GlutenAnalysis) -> some View {
        Image(systemName: analysis.result.icon)
            .font(.system(size: 56))
            .foregroundColor(analysis.result.color)

        Text(analysis.result.title(lang))
            .font(.title.bold())
            .foregroundColor(analysis.result.color)

        Text(analysis.reason.text(lang))
            .font(.subheadline)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)

        if arabicUnavailable && lang.isArabic {
            Text(lang.t(.arabicOCRUnavailable))
                .font(.footnote)
                .foregroundColor(AppColor.warning)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }

        GroupBox(lang.t(.extractedText)) {
            Text(highlighted(extractedText, matches: analysis.matches))
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private func errorSection(_ message: String) -> some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .font(.system(size: 48))
            .foregroundColor(AppColor.warning)

        Text(message)
            .font(.subheadline)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)

        Button(lang.t(.tryAgain)) {
            Task { await runAnalysis() }
        }
        .primaryButton(color: AppColor.warning)
        .padding(.horizontal)
    }

    // MARK: - Logic

    private func runAnalysis() async {
        isAnalyzing = true
        errorMessage = nil
        analysis = nil

        guard let capturedImage else {
            errorMessage = lang.t(.noPhoto)
            isAnalyzing = false
            return
        }

        do {
            let ocr = try await OCRService.recognizeText(in: capturedImage, preferArabic: lang.isArabic)
            extractedText = ocr.text
            arabicUnavailable = !ocr.arabicSupported
            let result = GlutenAnalyzer.analyze(text: ocr.text,
                                                averageConfidence: ocr.averageConfidence)
            analysis = result
            saveToHistory(result, text: ocr.text, image: capturedImage)
        } catch let error as OCRError {
            errorMessage = error.message(lang)
        } catch {
            errorMessage = error.localizedDescription
        }
        isAnalyzing = false
    }

    /// Saves the finished scan so it shows up in "View Scan History" (FR9).
    private func saveToHistory(_ analysis: GlutenAnalysis, text: String, image: UIImage) {
        guard !didSave else { return }
        didSave = true

        let thumbnail = image
            .preparingThumbnail(of: CGSize(width: 600, height: 600))?
            .jpegData(compressionQuality: 0.7)

        modelContext.insert(ScanRecord(result: analysis.result,
                                       reason: analysis.reason,
                                       extractedText: text,
                                       thumbnail: thumbnail))
        try? modelContext.save()
    }

    /// Builds the extracted text with matched ingredients highlighted (FR6).
    private func highlighted(_ text: String, matches: [GlutenMatch]) -> AttributedString {
        var attributed = AttributedString(text)
        for match in matches {
            guard let range = Range(match.range, in: text),
                  let lower = AttributedString.Index(range.lowerBound, within: attributed),
                  let upper = AttributedString.Index(range.upperBound, within: attributed)
            else { continue }

            let color = (match.severity == .definite) ? AppColor.danger : AppColor.warning
            attributed[lower..<upper].backgroundColor = color.opacity(0.3)
            attributed[lower..<upper].font = .body.bold()
        }
        return attributed
    }
}

#Preview {
    NavigationStack {
        ResultView(capturedImage: nil)
    }
    .modelContainer(for: ScanRecord.self, inMemory: true)
}
