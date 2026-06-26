import SwiftUI

struct UnlockView: View {
    @EnvironmentObject private var appState: AppState
    @State private var password = ""
    @State private var isConfirmingVaultReplacement = false

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
        }
        .padding()
        .onChange(of: appState.canReplaceCorruptedVault) { _, canReplace in
            if !canReplace {
                isConfirmingVaultReplacement = false
            }
        }
    }

    private func submitPassword() {
        let submittedPassword = password
        password = ""
        appState.createOrUnlockVault(password: submittedPassword)
    }
}
