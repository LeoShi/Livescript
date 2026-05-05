//
//  ContentView.swift
//  Livescript
//
//  Created by Lei S on 2026/5/5.
//

import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var viewModel: TranscriptionViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            transcriptList
            Divider()
            footer
        }
        .padding(14)
        .frame(minWidth: 520, minHeight: 340)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(FloatingWindowConfigurator().allowsHitTesting(false))
    }

    private var header: some View {
        HStack(spacing: 10) {
            Picker("Source", selection: $viewModel.sourceMode) {
                Text("Mic").tag(TranscriptSourceMode.mic)
                Text("System").tag(TranscriptSourceMode.system)
                Text("Mixed").tag(TranscriptSourceMode.mixed)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 240)
            .disabled(viewModel.isRunning)

            Spacer()

            Text(viewModel.captureHiddenStatus)
                .font(.caption)
                .foregroundStyle(.secondary)

            Menu("Model") {
                Button("Choose Local Model Folder") { viewModel.chooseModelFolder() }
                Button("Clear Local Model Folder") { viewModel.clearModelFolder() }
                if !viewModel.modelFolderPath.isEmpty {
                    Divider()
                    Text(viewModel.modelFolderPath)
                }
            }

            Button(viewModel.isRunning ? "Stop" : "Start") {
                if viewModel.isRunning {
                    viewModel.stop()
                } else {
                    Task { await viewModel.start() }
                }
            }
            .keyboardShortcut("s", modifiers: [.command])
        }
    }

    private var transcriptList: some View {
        SelectableTranscriptTextView(attributedText: transcriptAttributedText)
    }

    private var transcriptAttributedText: NSAttributedString {
        let full = NSMutableAttributedString()
        let bodyColor = NSColor.labelColor
        let baseFont = NSFont.preferredFont(forTextStyle: .body)
        var previousSpeaker: String?

        for segment in viewModel.segments {
            let speaker = segment.speakerLabel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let text = segment.text

            if !speaker.isEmpty, speaker != previousSpeaker {
                let label = NSAttributedString(
                    string: "\(speaker): ",
                    attributes: [
                        .font: baseFont,
                        .foregroundColor: speakerColor(for: speaker)
                    ]
                )
                full.append(label)
            }

            let content = NSAttributedString(
                string: text + "\n",
                attributes: [
                    .font: baseFont,
                    .foregroundColor: bodyColor
                ]
            )
            full.append(content)
            previousSpeaker = speaker.isEmpty ? previousSpeaker : speaker
        }

        return full
    }

    private func speakerColor(for speaker: String) -> NSColor {
        switch speaker.lowercased() {
        case "you":
            return .systemBlue
        case "system":
            return .systemGreen
        default:
            return .systemOrange
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let progress = viewModel.modelDownloadProgress, progress < 1.0 {
                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.modelPreparationMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ProgressView(value: progress, total: 1.0)
                }
            } else {
                Text(viewModel.modelPreparationMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: 8) {
                Text(viewModel.systemCaptureStatus)
                    .font(.caption2)
                    .foregroundStyle(systemStatusColor)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                if viewModel.systemCaptureStatus.contains("denied") || viewModel.systemCaptureStatus.contains("error") {
                    Button("Open Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .controlSize(.small)
                }
            }

            HStack(spacing: 12) {
                levelMeter(label: "You", value: viewModel.micLevel, color: .blue)
                levelMeter(label: "System", value: viewModel.systemLevel, color: .green)
            }

            HStack {
                Text("Session: \(viewModel.elapsedText)")
                    .font(.footnote.monospacedDigit())
                Spacer()
                Text(viewModel.statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Menu("Export") {
                    Button("Export TXT") { viewModel.export(format: .txt) }
                    Button("Export Markdown") { viewModel.export(format: .md) }
                }
            }
        }
    }

    private var systemStatusColor: Color {
        let status = viewModel.systemCaptureStatus
        if status.contains("denied") || status.contains("error") {
            return .red
        }
        if status.contains("running") {
            return .green
        }
        return .secondary
    }

    private func levelMeter(label: String, value: Float, color: Color) -> some View {
        let normalized = min(1.0, max(0.0, Double(value) * 12.0))
        return HStack(spacing: 6) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading)
            ProgressView(value: normalized)
                .progressViewStyle(.linear)
                .tint(color)
                .frame(maxWidth: .infinity)
        }
    }
}
