import Foundation
import SwiftUI

struct UnlockView: View {
    @EnvironmentObject private var appState: AppState
    @State private var password = ""
    @State private var isConfirmingVaultReplacement = false
    @State private var isConfirmingNewVault = false
    @State private var archivedVaultPendingDeletion: VaultService.ArchivedVault?

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.64)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    unlockPanel
                    recoveryPanel
                    archivedVaultsPanel
                }
                .padding(.horizontal, 28)
                .padding(.top, 88)
                .padding(.bottom, 28)
                .frame(maxWidth: 620)
            }
        }
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

    private var unlockPanel: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.fill")
                .font(.title2)
                .foregroundStyle(.white.opacity(0.58))

            Text("Locked")
                .font(.title.weight(.semibold))
                .foregroundStyle(.white.opacity(0.94))

            Text(appState.vaultNeedsCreation ? "Create vault" : "Unlock vault")
                .foregroundStyle(.white.opacity(0.58))

            SecureField("Password", text: $password)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)
                .onSubmit(submitPassword)

            if let errorMessage = appState.authenticationErrorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(appState.vaultNeedsCreation ? "Create" : "Unlock") {
                submitPassword()
            }
            .disabled(password.isEmpty)
            .buttonStyle(.glassProminent)
        }
        .padding(.horizontal, 44)
        .padding(.vertical, 34)
        .frame(maxWidth: .infinity)
        .glassPanel(cornerRadius: 36, material: .regularMaterial, strokeOpacity: 0.34)
    }

    @ViewBuilder
    private var recoveryPanel: some View {
        if appState.canReplaceCorruptedVault || !appState.vaultNeedsCreation {
            VStack(spacing: 12) {
                if appState.canReplaceCorruptedVault {
                    if isConfirmingVaultReplacement {
                        Text("This moves the current vault aside and starts a new empty vault.")
                            .foregroundStyle(.white.opacity(0.62))
                            .multilineTextAlignment(.center)

                        HStack {
                            Button("Cancel") {
                                isConfirmingVaultReplacement = false
                            }
                            .buttonStyle(.glass)

                            Button("Replace vault", role: .destructive) {
                                password = ""
                                isConfirmingVaultReplacement = false
                                appState.replaceCorruptedVaultAfterConfirmation()
                            }
                            .buttonStyle(.glassProminent)
                        }
                    } else {
                        Button("Replace corrupted vault") {
                            isConfirmingVaultReplacement = true
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !appState.vaultNeedsCreation {
                    if isConfirmingNewVault {
                        Text("This moves the current encrypted vault aside. It does not delete or decrypt it.")
                            .foregroundStyle(.white.opacity(0.62))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack {
                            Button("Cancel") {
                                isConfirmingNewVault = false
                            }
                            .buttonStyle(.glass)

                            Button("Start new vault", role: .destructive) {
                                password = ""
                                isConfirmingNewVault = false
                                appState.startNewVaultAfterForgettingPassword()
                            }
                            .buttonStyle(.glassProminent)
                        }
                    } else {
                        Button("Forgot password? Start new vault") {
                            isConfirmingNewVault = true
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.top, 2)
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var archivedVaultsPanel: some View {
        if !appState.archivedVaults.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Archived Vaults")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.66))

                ForEach(appState.archivedVaults) { archivedVault in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(archivedVault.fileName)
                                .lineLimit(1)

                            Text(byteCountLabel(archivedVault.byteCount))
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.58))
                        }

                        Spacer()

                        Button("Restore") {
                            password = ""
                            appState.restoreArchivedVault(id: archivedVault.id)
                        }
                        .buttonStyle(.glass)

                        Button("Delete", role: .destructive) {
                            archivedVaultPendingDeletion = archivedVault
                        }
                        .buttonStyle(.glass)
                    }
                    .padding(10)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .glassPanel(cornerRadius: 30, strokeOpacity: 0.28)
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
