//
//  RecentAppsView.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 11.07.25.
//

import SwiftUI
import Combine

struct RecentAppsView: View {
    @ObservedObject var viewModel: SimulatorManagerViewModel
    @ObservedObject var settings: SettingsViewModel
    
    var body: some View {
        if Settings().showRecentApps {
            ForEach(viewModel.recentInstalledApps, id: \.id) { appChange in
                Menu {
                    Button {
                        viewModel.didSelectAppDocumentFolder(for: appChange.app)
                    } label: {
                        Text("Documents Folder")
                    }
                    Button {
                        viewModel.didSelectAppPackageFolder(for: appChange.app)
                    } label: {
                        Text("App Package")
                    }
                    if appChange.app.hasUserDefaults {
                        Button {
                            viewModel.didSelectUserDefaultsFolder(for: appChange.app)
                        } label: {
                            Text("User Defaults")
                        }
                    }
                } label: {
                    Text(appChange.app.displayName)
                    Text(appChange.device.name + " " + appChange.device.osVersion)
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
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
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
