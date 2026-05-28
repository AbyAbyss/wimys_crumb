// ScanningView.swift
// Mirrors PScanning in proto-start-scan.jsx. Real engine data; no fake
// animation. Plan §8.2.
//
// Layout: 1.2 : 1 split. Left progress hero (percent, bar, files/ETA, mono
// current-path box, Pause/Cancel). Right "Biggest so far" live list, refreshed
// ~1s by AppModel from SQLite during the scan.

import SwiftUI

struct ScanningView: View {
    @Bindable var app: AppModel

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.cardGap) {
            progressHero
                .frame(maxWidth: .infinity)
            biggestList
                .frame(width: 400)
        }
        .padding(.horizontal, Spacing.screenH)
        .padding(.bottom, Spacing.screenV)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Progress hero

    private var progressHero: some View {
        Card(pad: 28) {
            VStack(alignment: .leading, spacing: 0) {
                Pill(
                    text: app.isPaused ? "Paused" : "Scanning",
                    color: .cCoral,
                    soft: .cCoralSoft,
                    leadingDot: true
                )

                Text("Sweeping \(app.currentVolume?.name ?? "your drive")")
                    .font(Theme.display(32, weight: .heavy))
                    .tracking(-0.8)
                    .foregroundStyle(Color.cInk)
                    .padding(.top, 12)
                    .padding(.bottom, 4)

                Text("We'll group similar things and show you the big stuff.")
                    .font(Theme.body(13))
                    .foregroundStyle(Color.cInk2)

                HStack(alignment: .lastTextBaseline, spacing: 14) {
                    HStack(alignment: .lastTextBaseline, spacing: 0) {
                        Text("\(Int(app.scanProgress * 100))")
                            .font(Theme.display(84, weight: .heavy))
                            .tracking(-3)
                            .foregroundStyle(Color.cInk)
                            .monospacedDigit()
                        Text("%")
                            .font(Theme.display(36, weight: .heavy))
                            .foregroundStyle(Color.cCoral)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        ProgressBarView(fraction: app.scanProgress, color: .cCoral, height: 10)
                        HStack {
                            Text("\(app.filesScanned.formatted(.number)) files")
                                .font(Theme.body(12))
                                .foregroundStyle(Color.cInk2)
                            Spacer()
                            if let eta = app.etaSeconds, eta > 0 {
                                Text("~\(eta)s left")
                                    .font(Theme.body(12))
                                    .foregroundStyle(Color.cInk2)
                            } else {
                                Text("collecting…")
                                    .font(Theme.body(12))
                                    .foregroundStyle(Color.cInk3)
                            }
                        }
                    }
                }
                .padding(.vertical, 18)

                // Monospace current-path box.
                VStack(alignment: .leading, spacing: 4) {
                    Text("currently scanning")
                        .font(Theme.body(11))
                        .foregroundStyle(Color.cInk3)
                    Text(app.currentScanPath.isEmpty ? "—" : app.currentScanPath)
                        .font(Theme.mono(12))
                        .foregroundStyle(Color.cInk2)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.cPanel)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.cLine, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                HStack(spacing: 8) {
                    Button(action: togglePause) {
                        HStack(spacing: 6) {
                            IconView(icon: app.isPaused ? .play : .pause, size: 14, weight: .bold)
                            Text(app.isPaused ? "Resume" : "Pause")
                                .font(Theme.body(13, weight: .semibold))
                        }
                        .foregroundStyle(Color.cInk)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(Color.cPaper)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Color.cLine2, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Button(action: { app.cancelScan() }) {
                        Text("Cancel")
                            .font(Theme.body(13, weight: .semibold))
                            .foregroundStyle(Color.cInk2)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Color.cLine2, lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 18)
            }
        }
    }

    private func togglePause() {
        if app.isPaused { app.resumeScan() } else { app.pauseScan() }
    }

    // MARK: - Biggest so far

    private var biggestList: some View {
        Card(pad: 20) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("BIGGEST SO FAR")
                        .font(Theme.body(14, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(Color.cInk)
                    Spacer()
                    Pill(text: "live", color: .cHoney, soft: .cHoneySoft)
                }
                .padding(.bottom, 12)

                if app.biggestSoFar.isEmpty {
                    Text("Walking the file tree…")
                        .font(Theme.body(13))
                        .foregroundStyle(Color.cInk3)
                        .padding(.vertical, 10)
                } else {
                    let maxSize = Double(app.biggestSoFar.map(\.totalSize).max() ?? 1)
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(app.biggestSoFar.enumerated()), id: \.element.id) { idx, dir in
                            BiggestRow(
                                dir: dir,
                                color: Color.aHues[idx % Color.aHues.count],
                                fraction: maxSize > 0 ? Double(dir.totalSize) / maxSize : 0
                            )
                        }
                    }
                }
            }
        }
    }
}

private struct BiggestRow: View {
    let dir: DirRow
    let color: Color
    let fraction: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                HStack(spacing: 7) {
                    IconView(icon: .folder, size: 14)
                        .foregroundStyle(color)
                    Text(dir.name)
                        .font(Theme.body(13, weight: .medium))
                        .foregroundStyle(Color.cInk)
                        .lineLimit(1)
                }
                Spacer()
                Text(Fmt.bytes(dir.totalSize))
                    .font(Theme.body(12))
                    .foregroundStyle(Color.cInk2)
                    .monospacedDigit()
            }
            ProgressBarView(fraction: fraction, color: color, height: 5)
        }
    }
}

#Preview {
    ScanningView(app: AppModel.previewScanning)
        .frame(width: 1280, height: 700)
        .background(Color.cBg)
}
