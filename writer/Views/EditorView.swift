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
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.64)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                toolbar

                HStack(alignment: .top, spacing: 14) {
                    notesSidebar
                    editorSurface
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, 22)
            .padding(.top, 58)
            .padding(.bottom, 22)
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
        }
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

    private var toolbar: some View {
        HStack(spacing: 12) {
            Spacer()

            if let statusMessage = appState.editorStatusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.62))
            }

            Toggle(
                "Auto Save",
                isOn: Binding(
                    get: { appState.isAutoSaveEnabled },
                    set: { appState.setAutoSaveEnabled($0) }
                )
            )
            .toggleStyle(.checkbox)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(.white.opacity(0.16), lineWidth: 1)
            }

            Button {
                appState.copySelectedNoteBodyToPasteboard()
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .help("Copy note text")
            .buttonStyle(.glass)

            Button {
                appState.saveEditorText()
            } label: {
                Image(systemName: "square.and.arrow.down")
            }
            .keyboardShortcut("s", modifiers: .command)
            .help("Save vault")
            .buttonStyle(.glass)

            Button {
                appState.lock()
            } label: {
                Image(systemName: "lock")
            }
            .help("Lock vault")
            .buttonStyle(.glassProminent)

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
        .frame(maxWidth: .infinity)
    }

    private var notesSidebar: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Notes")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.62))

                Spacer()

                Button {
                    appState.createNote()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.glass)
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
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .focused($focusedArea, equals: .noteList)
        }
        .padding(16)
        .frame(width: 226)
        .frame(maxHeight: .infinity)
        .glassPanel(cornerRadius: 30, strokeOpacity: 0.30)
    }

    private var editorSurface: some View {
        TextEditor(
            text: Binding(
                get: { appState.selectedNoteBody },
                set: { appState.updateSelectedNoteBody($0) }
            )
        )
        .font(.body)
        .foregroundStyle(.white.opacity(0.94))
        .scrollContentBackground(.hidden)
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(.white.opacity(0.26), lineWidth: 1.1)
        }
        .focused($focusedArea, equals: .editor)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
