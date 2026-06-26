import SwiftUI

struct EditorView: View {
    private enum FocusArea {
        case noteList
        case editor
    }

    @EnvironmentObject private var appState: AppState
    @State private var notePendingRename: VaultNote?
    @State private var renameTitle = ""
    @State private var notePendingDeletion: VaultNote?
    @FocusState private var focusedArea: FocusArea?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Notes")
                    .font(.title)

                Spacer()

                Toggle(
                    "Auto Save",
                    isOn: Binding(
                        get: { appState.isAutoSaveEnabled },
                        set: { appState.setAutoSaveEnabled($0) }
                    )
                )
                .toggleStyle(.checkbox)

                Button("Save") {
                    appState.saveEditorText()
                }
                .keyboardShortcut("s", modifiers: .command)

                Button("Lock") {
                    appState.lock()
                }

                Button("Notes") {
                    focusedArea = .noteList
                }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
                .frame(width: 0, height: 0)
                .opacity(0)
                .accessibilityHidden(true)

                Button("Editor") {
                    focusedArea = .editor
                }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
                .frame(width: 0, height: 0)
                .opacity(0)
                .accessibilityHidden(true)
            }

            if let statusMessage = appState.editorStatusMessage {
                Text(statusMessage)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                VStack(spacing: 8) {
                    HStack {
                        Text("Vault")
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button {
                            appState.createNote()
                        } label: {
                            Image(systemName: "plus")
                        }
                        .buttonStyle(.borderless)
                        .help("New note")
                    }

                    List(
                        appState.notes,
                        selection: Binding(
                            get: { appState.selectedNoteID },
                            set: { selectedID in
                                if let selectedID {
                                    appState.selectNote(id: selectedID)
                                }
                            }
                        )
                    ) { note in
                        Text(note.title)
                            .lineLimit(1)
                            .tag(note.id)
                            .contextMenu {
                                Button("Rename") {
                                    notePendingRename = note
                                    renameTitle = note.title
                                }

                                Button("Delete", role: .destructive) {
                                    notePendingDeletion = note
                                }
                            }
                    }
                    .focused($focusedArea, equals: .noteList)
                }
                .frame(width: 180)

                TextEditor(
                    text: Binding(
                        get: { appState.selectedNoteBody },
                        set: { appState.updateSelectedNoteBody($0) }
                    )
                )
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .background(Color.black.opacity(0.04))
                .border(.secondary)
                .focused($focusedArea, equals: .editor)
            }
        }
        .padding()
        .fontDesign(.monospaced)
        .onAppear {
            focusedArea = .editor
        }
        .onMoveCommand { direction in
            guard focusedArea == .noteList else {
                return
            }

            switch direction {
            case .up:
                appState.selectPreviousNote()
            case .down:
                appState.selectNextNote()
            default:
                break
            }
        }
        .sheet(item: $notePendingRename) { note in
            VStack(alignment: .leading, spacing: 12) {
                Text("Rename Note")
                    .font(.headline)

                TextField("Title", text: $renameTitle)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Spacer()

                    Button("Cancel") {
                        notePendingRename = nil
                    }

                    Button("Rename") {
                        appState.renameNote(id: note.id, title: renameTitle)
                        notePendingRename = nil
                    }
                }
            }
            .padding()
            .frame(width: 320)
        }
        .alert("Delete Note?", isPresented: deleteConfirmationBinding, presenting: notePendingDeletion) { note in
            Button("Cancel", role: .cancel) {
                notePendingDeletion = nil
            }

            Button("Delete", role: .destructive) {
                appState.deleteNote(id: note.id)
                notePendingDeletion = nil
            }
        } message: { note in
            Text("This removes \"\(note.title)\" from the vault.")
        }
    }

    private var deleteConfirmationBinding: Binding<Bool> {
        Binding(
            get: { notePendingDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    notePendingDeletion = nil
                }
            }
        )
    }
}
