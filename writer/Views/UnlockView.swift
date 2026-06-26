import Foundation
import SwiftUI

struct UnlockView: View {
    @EnvironmentObject private var appState: AppState
    @State private var password = ""
    @State private var isConfirmingVaultReplacement = false
    @State private var isConfirmingNewVault = false
    @State private var archivedVaultPendingDeletion: VaultService.ArchivedVault?

    var body: some View {
        VStack(spacing: 16) {
            Text("Locked")
                .font(.title)

            Text(appState.vaultNeedsCreation ? "Create vault" : "Unlock vault")
                .foregroundStyle(.secondary)

            SecureField("Password", text: $password)
                .frame(width: 240)
                .onSubmit(submitPassword)

            if let errorMessage = appState.authenticationErrorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            }

            Button(appState.vaultNeedsCreation ? "Create" : "Unlock") {
                submitPassword()
            }
            .disabled(password.isEmpty)

            if appState.canReplaceCorruptedVault {
                if isConfirmingVaultReplacement {
                    Text("This moves the current vault aside and starts a new empty vault.")
                        .foregroundStyle(.secondary)

                    HStack {
                        Button("Cancel") {
                            isConfirmingVaultReplacement = false
                        }

                        Button("Replace vault", role: .destructive) {
                            password = ""
                            isConfirmingVaultReplacement = false
                            appState.replaceCorruptedVaultAfterConfirmation()
                        }
                    }
                } else {
                    Button("Replace corrupted vault") {
                        isConfirmingVaultReplacement = true
                    }
                }
            }

            if !appState.vaultNeedsCreation {
                Divider()
                    .frame(width: 240)

                if isConfirmingNewVault {
                    Text("This moves the current encrypted vault aside. It does not delete or decrypt it.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(width: 300)

                    HStack {
                        Button("Cancel") {
                            isConfirmingNewVault = false
                        }

                        Button("Start new vault", role: .destructive) {
                            password = ""
                            isConfirmingNewVault = false
                            appState.startNewVaultAfterForgettingPassword()
                        }
                    }
                } else {
                    Button("Forgot password? Start new vault") {
                        isConfirmingNewVault = true
                    }
                }
            }

            if !appState.archivedVaults.isEmpty {
                Divider()
                    .frame(width: 300)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Archived Vaults")
                        .foregroundStyle(.secondary)

                    ForEach(appState.archivedVaults) { archivedVault in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(archivedVault.fileName)
                                    .lineLimit(1)

                                Text("\(byteCountLabel(archivedVault.byteCount))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Button("Restore") {
                                password = ""
                                appState.restoreArchivedVault(id: archivedVault.id)
                            }

                            Button("Delete", role: .destructive) {
                                archivedVaultPendingDeletion = archivedVault
                            }
                        }
                    }
                }
                .frame(width: 360)
            }
        }
        .padding()
        .onChange(of: appState.canReplaceCorruptedVault) { _, canReplace in
            if !canReplace {
                isConfirmingVaultReplacement = false
            }
        }
        .onChange(of: appState.vaultNeedsCreation) { _, needsCreation in
            if needsCreation {
                isConfirmingNewVault = false
            }
        }
        .alert(
            "Delete Archived Vault?",
            isPresented: archivedVaultDeletionBinding,
            presenting: archivedVaultPendingDeletion
        ) { archivedVault in
            Button("Cancel", role: .cancel) {
                archivedVaultPendingDeletion = nil
            }

            Button("Delete", role: .destructive) {
                appState.deleteArchivedVault(id: archivedVault.id)
                archivedVaultPendingDeletion = nil
            }
        } message: { archivedVault in
            Text("This permanently deletes \(archivedVault.fileName). It cannot be restored from this app.")
        }
    }

    private func submitPassword() {
        let submittedPassword = password
        password = ""
        appState.createOrUnlockVault(password: submittedPassword)
    }

    private func byteCountLabel(_ byteCount: Int64) -> String {
        ByteCountFormatter.string(
            fromByteCount: byteCount,
            countStyle: .file
        )
    }

    private var archivedVaultDeletionBinding: Binding<Bool> {
        Binding(
            get: { archivedVaultPendingDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    archivedVaultPendingDeletion = nil
                }
            }
        )
    }
}
