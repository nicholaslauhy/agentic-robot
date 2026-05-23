//
//  ReportsListView.swift
//  agentic robot
//
//  Created by q2 on 23/5/26.
//

import SwiftUI
import FirebaseFirestore

// MARK: - Reports List View
struct ReportsListView: View {

    @State private var reports: [ReportEntry] = []
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var searchText = ""
    @State private var selectedReport: ReportEntry? = nil
    @State private var selectedPDFURL: URL? = nil

    // Filtered list based on search
    var filteredReports: [ReportEntry] {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return reports
        }
        let query = searchText.lowercased()
        return reports.filter {
            $0.plate.lowercased().contains(query) ||
            $0.reportNo.lowercased().contains(query) ||
            $0.carType.lowercased().contains(query) ||
            $0.generatedBy.lowercased().contains(query) ||
            $0.barcodeId.contains(query)
        }
    }

    var body: some View {
        ZStack {
            SubtleHTXBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {

                // MARK: Search Bar
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)

                    TextField("Search by plate, officer, report no…", text: $searchText)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(12)
                .background(Color(.systemBackground).opacity(0.9))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(HTXTheme.primaryPurple.opacity(0.25), lineWidth: 1)
                )
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 8)

                // MARK: Content
                if isLoading {
                    Spacer()
                    ProgressView("Loading reports…")
                        .tint(HTXTheme.primaryPurple)
                    Spacer()

                } else if let errorMessage {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.largeTitle)
                            .foregroundColor(.orange)
                        Text(errorMessage)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                        Button("Retry") { fetchReports() }
                            .buttonStyle(.borderedProminent)
                            .tint(HTXTheme.primaryPurple)
                    }
                    .padding()
                    Spacer()

                } else if filteredReports.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: searchText.isEmpty ? "folder.badge.questionmark" : "magnifyingglass")
                            .font(.system(size: 44))
                            .foregroundColor(HTXTheme.primaryPurple.opacity(0.5))
                        Text(searchText.isEmpty ? "No reports yet." : "No reports match \"\(searchText)\".")
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    Spacer()

                } else {
                    // MARK: Report count badge
                    HStack {
                        Text("\(filteredReports.count) report\(filteredReports.count == 1 ? "" : "s")")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                        Spacer()
                        Button {
                            fetchReports()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.subheadline)
                                .foregroundColor(HTXTheme.primaryPurple)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 4)

                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(filteredReports) { report in
                                ReportRowCard(report: report)
                                    .onTapGesture {
                                        selectedReport = report
                                    }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 24)
                    }
                }
            }
        }
        .navigationTitle("Existing Reports")
        .navigationBarTitleDisplayMode(.inline)
        .tint(HTXTheme.primaryPurple)
        .onAppear { fetchReports() }
        .sheet(item: $selectedReport) { report in
            ReportDetailSheet(report: report) { url in
                selectedReport = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    selectedPDFURL = url
                }
            }
        }
        .sheet(item: $selectedPDFURL) { url in
            ReportPDFPreviewView(url: url)
        }
    }

    // MARK: - Fetch from Firestore
    private func fetchReports() {
        isLoading = true
        errorMessage = nil

        Firestore.firestore()
            .collection("reports")
            .order(by: "createdAt", descending: true)
            .getDocuments { snapshot, error in
                DispatchQueue.main.async {
                    isLoading = false

                    if let error {
                        self.errorMessage = error.localizedDescription
                        return
                    }

                    self.reports = (snapshot?.documents ?? []).compactMap { doc in
                        let data = doc.data()
                        guard
                            let reportNo = data["reportNo"] as? String,
                            let plate    = data["plate"]    as? String
                        else { return nil }

                        let createdAt = (data["createdAt"] as? Timestamp)?.dateValue()

                        return ReportEntry(
                            id:             doc.documentID,
                            reportNo:       reportNo,
                            plate:          plate,
                            carType:        data["carType"]        as? String ?? "-",
                            generatedBy:    data["generatedBy"]    as? String ?? "-",
                            detectionCount: data["detectionCount"] as? Int    ?? 0,
                            createdAt:      createdAt,
                            barcodeId:      data["barcodeId"]      as? String ?? doc.documentID,
                            pdfFileName:   data["pdfFileName"]   as? String,
                            pdfBase64:     data["pdfBase64"]     as? String
                        )
                    }
                }
            }
    }
}

// MARK: - Report Row Card
private struct ReportRowCard: View {
    let report: ReportEntry

    private var generatedByText: String {
        let trimmed = report.generatedBy.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed == "-" ? "Not recorded" : trimmed
    }

    var body: some View {
        HStack(spacing: 14) {

            // Left colour strip + icon
            VStack {
                Image(systemName: "doc.text.fill")
                    .font(.title3)
                    .foregroundColor(.white)
            }
            .frame(width: 44, height: 44)
            .background(
                LinearGradient(
                    colors: [HTXTheme.primaryPurple, HTXTheme.secondaryPurple],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 11))

            // Centre: plate + report info
            VStack(alignment: .leading, spacing: 4) {
                Text(report.plate)
                    .font(.headline)
                    .foregroundColor(.primary)

                Text(report.reportNo)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(HTXTheme.primaryPurple)

                HStack(spacing: 6) {
                    Text(report.carType)
                    Text("·")
                    Text("\(report.detectionCount) case\(report.detectionCount == 1 ? "" : "s")")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }

            Spacer()

            // Right: date + chevron
            VStack(alignment: .trailing, spacing: 4) {
                Text(report.shortDate)
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(HTXTheme.primaryPurple.opacity(0.6))
            }
        }
        .padding(14)
        .background(Color(.systemBackground).opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(HTXTheme.primaryPurple.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
    }
}

// MARK: - Report Detail Sheet
struct ReportDetailSheet: View {
    let report: ReportEntry
    var onViewPDF: (URL) -> Void
    @Environment(\.dismiss) var dismiss
    @State private var pdfErrorMessage: String? = nil

    private var generatedByText: String {
        let trimmed = report.generatedBy.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed == "-" ? "Not recorded" : trimmed
    }

    var body: some View {
        NavigationStack {
            ZStack {
                SubtleHTXBackground()
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {

                        // Header card
                        VStack(spacing: 6) {
                            Image(systemName: "doc.text.fill")
                                .font(.system(size: 40))
                                .foregroundColor(HTXTheme.primaryPurple)

                            Text(report.plate)
                                .font(.largeTitle.weight(.black))
                                .foregroundColor(.primary)

                            Text(report.reportNo)
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(HTXTheme.primaryPurple)

                            Label("Generated by \(generatedByText)", systemImage: "person.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.secondary)
                                .padding(.top, 2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                        .background(Color(.systemBackground).opacity(0.9))
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .padding(.horizontal)

                        // Details card
                        VStack(spacing: 0) {
                            DetailRow(label: "Report No.",    value: report.reportNo)
                            Divider().padding(.leading, 16)
                            DetailRow(label: "Plate",         value: report.plate)
                            Divider().padding(.leading, 16)
                            DetailRow(label: "Vehicle Type",  value: report.carType)
                            Divider().padding(.leading, 16)
                            DetailRow(label: "Damage Cases",  value: "\(report.detectionCount)")
                            Divider().padding(.leading, 16)
                            DetailRow(label: "Generated By",  value: generatedByText)
                            Divider().padding(.leading, 16)
                            DetailRow(label: "Date & Time",   value: report.dateString)
                        }
                        .background(Color(.systemBackground).opacity(0.9))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(HTXTheme.primaryPurple.opacity(0.12), lineWidth: 1)
                        )
                        .padding(.horizontal)

                        // Barcode ID card
                        VStack(spacing: 8) {
                            Text("Barcode ID")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.secondary)

                            Text(report.barcodeId)
                                .font(.system(.title2, design: .monospaced).weight(.bold))
                                .foregroundColor(HTXTheme.primaryPurple)
                                .tracking(3)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(HTXTheme.primaryPurple.opacity(0.07))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(HTXTheme.primaryPurple.opacity(0.2), lineWidth: 1)
                        )
                        .padding(.horizontal)

                        if let pdfErrorMessage {
                            Text(pdfErrorMessage)
                                .font(.footnote.weight(.semibold))
                                .foregroundColor(.red)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }

                        Button {
                            guard let url = ReportStore.resolvedPDFURL(for: report) else {
                                pdfErrorMessage = "This report record exists, but the PDF file is not available. Generate it again with the updated app so the PDF can be saved."
                                return
                            }
                            pdfErrorMessage = nil
                            onViewPDF(url)
                        } label: {
                            HStack {
                                Image(systemName: "doc.richtext.fill")
                                Text(report.hasPDF ? "View PDF Report" : "PDF Not Saved")
                            }
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(report.hasPDF ? HTXTheme.primaryPurple : Color.gray)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .padding(.horizontal)

                        Spacer().frame(height: 10)
                    }
                    .padding(.top, 16)
                }
            }
            .navigationTitle("Report Detail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(HTXTheme.primaryPurple)
                        .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Detail Row
private struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(width: 120, alignment: .leading)

            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.primary)
                .multilineTextAlignment(.leading)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
