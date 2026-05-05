//
//  ContentView.swift
//  Livescript
//
//  Created by Lei S on 2026/5/5.
//

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
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(viewModel.segments) { segment in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(segment.timestamp, style: .time)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(segment.language.rawValue.uppercased())
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                            Text(segment.text)
                                .font(.body)
                                .textSelection(.enabled)
                        }
                        .id(segment.id)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .onChange(of: viewModel.segments.count) { _, _ in
                if let last = viewModel.segments.last {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
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
}
