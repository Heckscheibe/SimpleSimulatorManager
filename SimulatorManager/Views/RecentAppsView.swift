//
//  RecentAppsView.swift
//  SimulatorManager
//
//  Created by AI Assistant on 11.07.25.
//

import SwiftUI

struct RecentAppsView: View {
    @ObservedObject var viewModel: SimulatorManagerViewModel
    @ObservedObject var settings: SettingsViewModel
    
    var body: some View {
        if Settings().showRecentApps {
            VStack(alignment: .leading, spacing: 8) {
                if !viewModel.recentAppChanges.isEmpty {
                    HStack {
                        Image(systemName: "clock")
                            .foregroundColor(.secondary)
                        Text("Recently Added/Removed Apps")
                            .font(.headline)
                            .foregroundColor(.primary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(viewModel.recentAppChanges.prefix(10)) { change in
                                RecentAppRow(change: change)
                            }
                        }
                        .padding(.horizontal, 12)
                    }
                    .frame(maxHeight: 300)
                    
                } else {
                    HStack {
                        Image(systemName: "clock")
                            .foregroundColor(.secondary)
                        Text("No recent app changes")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }
        }
    }
}

struct RecentAppRow: View {
    let change: AppChange
    
    var body: some View {
        HStack(spacing: 12) {
            // App icon
            Image(systemName: change.app.iconName)
                .foregroundColor(.accentColor)
                .frame(width: 20, height: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                // App name and update type
                HStack {
                    Text(change.app.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    changeTypeLabel
                }
                
                // Bundle identifier and device info
                HStack {
                    Text(change.app.bundleIdentifier)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    Text(change.device.name)
                        .font(.caption2)
                        .foregroundColor(.accentColor)
                        .lineLimit(1)
                }
                
                // Timestamp
                Text(change.timestamp, style: .relative)
                    .font(.caption2)
                    .foregroundColor(.accentColor)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(0.05))
        )
        .contextMenu {
            contextMenuItems
        }
    }
    
    @ViewBuilder private var changeTypeLabel: some View {
        switch change.changeType {
        case .installed:
            Label("New", systemImage: "plus.circle.fill")
                .labelStyle(.iconOnly)
                .foregroundColor(.green)
        case .removed:
            Label("Removed", systemImage: "minus.circle.fill")
                .labelStyle(.iconOnly)
                .foregroundColor(.red)
        }
    }
    
    @ViewBuilder private var contextMenuItems: some View {
        if let packageURL = change.app.appPackageURL {
            Button("Show in Finder") {
                NSWorkspace.shared.selectFile(packageURL.path, inFileViewerRootedAtPath: "")
            }
        }
        
        if let documentsURL = change.app.appDocumentsFolderURL {
            Button("Show Documents Folder") {
                NSWorkspace.shared.open(documentsURL)
            }
        }
        
        Button("Copy Bundle Identifier") {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(change.app.bundleIdentifier, forType: .string)
        }
        
        Divider()
        
        Button("Copy App Info") {
            let appInfo = """
            App: \(change.app.displayName)
            Bundle ID: \(change.app.bundleIdentifier)
            Device: \(change.device.name) (\(change.device.osVersion))
            Changed: \(change.timestamp.formatted())
            Type: \(change.changeType)
            """
            
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(appInfo, forType: .string)
        }
    }
}

// MARK: - Preview

#Preview {
    let viewModel = SimulatorManagerViewModel()
    
    RecentAppsView(viewModel: viewModel, settings: SettingsViewModel())
        .frame(width: 320)
}
