// StartView.swift
// Drive list + scan entry point.
// Mirrors `PStart` in proto-start-scan.jsx, but with real mounted volumes
// (FileManager.mountedVolumeURLs + resource keys).

import SwiftUI

struct StartView: View {
    @Bindable var app: AppModel

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.cardGap) {
            heroCard
                .frame(maxWidth: .infinity)
            drivesCard
                .frame(width: 420)
        }
        .padding(.horizontal, Spacing.screenH)
        .padding(.bottom, Spacing.screenV)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Hero card
    // Custom surface — gradient bg + dotted texture + line2 border. Doesn't use
    // the `Card` component because Card's paper bg would hide the gradient.

    private var heroCard: some View {
        ZStack(alignment: .topLeading) {
            DotTexture()
                .opacity(0.18)
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 18) {
                Pill(text: "● Ready to scan", color: .cCoral, soft: .cPaper)

                Text("Where did\nyour space go?")
                    .font(Theme.display(56, weight: .heavy))
                    .tracking(-1.5)
                    .lineSpacing(2)
                    .foregroundStyle(Color.cInk)
                    .frame(maxWidth: 480, alignment: .leading)
                    .padding(.top, 4)

                Text("We'll sweep your drive, group what's eating space, and tell you what's safe to delete.")
                    .font(Theme.body(15))
                    .foregroundStyle(Color.cInk2)
                    .lineSpacing(4)
                    .frame(maxWidth: 440, alignment: .leading)

                Spacer(minLength: 0)

                HStack(spacing: 12) {
                    Button(action: scanBootVolume) {
                        HStack(spacing: 10) {
                            IconView(icon: .search, size: 17, weight: .bold)
                            Text("Scan \(bootVolumeName)")
                                .font(Theme.body(15, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 14)
                        .background(Color.cInk)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .shadow(color: Color.cInk.opacity(0.25), radius: 18, x: 0, y: 6)
                    }
                    .buttonStyle(PressedButtonStyle())

                    Button(action: { app.pickFolderAndScan() }) {
                        Text("Pick a specific folder…")
                            .font(Theme.body(14, weight: .medium))
                            .underline()
                            .foregroundStyle(Color.cInk)
                            .padding(.vertical, 14)
                            .padding(.horizontal, 8)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(32)
        .background(
            LinearGradient(
                colors: [Color.cHoneySoft, Color.cCoralSoft],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Color.cLine2, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }

    private var bootVolumeName: String {
        if let boot = app.volumes.first(where: { $0.url == URL(fileURLWithPath: "/") }) {
            return boot.name
        }
        return app.currentVolume?.name ?? "Macintosh HD"
    }

    private func scanBootVolume() {
        let target = app.volumes.first(where: { $0.url == URL(fileURLWithPath: "/") })
                  ?? app.volumes.first
        if let target { app.startScan(volume: target) }
    }

    // MARK: - Drives card

    private var drivesCard: some View {
        Card(pad: 20) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("DRIVES")
                        .font(Theme.body(14, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(Color.cInk)
                    Spacer()
                    Button(action: { app.refreshVolumes() }) {
                        IconView(icon: .refresh, size: 15, weight: .medium)
                            .foregroundStyle(Color.cInk2)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 14)

                if app.volumes.isEmpty {
                    Text("No volumes detected.")
                        .font(Theme.body(13))
                        .foregroundStyle(Color.cInk2)
                        .padding(.vertical, 12)
                } else {
                    VStack(spacing: 14) {
                        ForEach(Array(app.volumes.enumerated()), id: \.element.id) { idx, vol in
                            DriveRow(volume: vol, index: idx,
                                     onScan: { app.startScan(volume: vol) })
                        }
                    }
                }

                // Last scans
                if !app.recentScans.isEmpty {
                    Divider().background(Color.cLine).padding(.top, 16)
                    Text("Last scans")
                        .font(Theme.body(13, weight: .bold))
                        .foregroundStyle(Color.cInk)
                        .padding(.top, 14)
                        .padding(.bottom, 8)

                    VStack(spacing: 0) {
                        ForEach(app.recentScans) { scan in
                            Button(action: { /* Phase 4: load this snapshot */ }) {
                                HStack {
                                    Text(scan.volumeName)
                                        .font(Theme.body(12))
                                        .foregroundStyle(Color.cInk)
                                    Spacer()
                                    Text(Fmt.relative(scan.startedAt))
                                        .font(Theme.body(12))
                                        .foregroundStyle(Color.cInk2)
                                }
                                .padding(.vertical, 7)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Drive row

private struct DriveRow: View {
    let volume: VolumeInfo
    let index: Int
    let onScan: () -> Void

    private var donutColor: Color {
        if volume.isAlmostFull { return .cRed }
        let palette: [Color] = [.cCoral, .cHoney, .cSage]
        return palette[index % palette.count]
    }

    var body: some View {
        HStack(spacing: 12) {
            DonutView(fraction: volume.fractionUsed, size: 56, stroke: 7,
                      color: donutColor, track: .cLine) {
                Text("\(Int(volume.fractionUsed * 100))%")
                    .font(Theme.body(11, weight: .bold))
                    .foregroundStyle(Color.cInk)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(volume.name)
                        .font(Theme.body(14, weight: .semibold))
                        .foregroundStyle(Color.cInk)
                    if volume.isAlmostFull {
                        Pill(text: "almost full", color: .cRed, soft: .cRedSoft)
                    }
                }
                Text("\(Fmt.bytes(volume.used)) used of \(Fmt.bytes(volume.totalCapacity)) · \(volume.kind.label)")
                    .font(Theme.body(12))
                    .foregroundStyle(Color.cInk2)
            }
            Spacer(minLength: 8)
            Button(action: onScan) {
                Text("Scan")
                    .font(Theme.body(12, weight: .semibold))
                    .foregroundStyle(Color.cInk)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(Color.cPanel)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Pressed button style (translateY(2px) on press)

private struct PressedButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .offset(y: configuration.isPressed ? 2 : 0)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

// MARK: - Dot texture overlay (hero card)

private struct DotTexture: View {
    var body: some View {
        Canvas { ctx, size in
            let spacing: CGFloat = 12
            let radius: CGFloat = 0.8
            var y: CGFloat = 0
            while y < size.height {
                var x: CGFloat = 0
                while x < size.width {
                    let r = CGRect(x: x, y: y, width: radius * 2, height: radius * 2)
                    ctx.fill(Path(ellipseIn: r), with: .color(.cInk))
                    x += spacing
                }
                y += spacing
            }
        }
    }
}

#Preview {
    StartView(app: AppModel.previewStart)
        .frame(width: 1280, height: 700)
        .background(Color.cBg)
}
