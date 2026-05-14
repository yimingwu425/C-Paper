import SwiftUI

struct LoginView: View {
    @Environment(AuthService.self) private var authService
    @State private var email = ""
    @State private var password = ""
    @State private var nickname = ""
    @State private var isRegistering = false
    @State private var isLoading = false
    @State private var error: String?

    var body: some View {
        GlassCard {
            VStack(spacing: 16) {
                Text(isRegistering ? "注册" : "登录")
                    .font(.title2.weight(.bold))

                TextField("邮箱", text: $email)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.emailAddress)
                    .autocapitalization(.none)

                SecureField("密码", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(isRegistering ? .newPassword : .password)

                if isRegistering {
                    TextField("昵称", text: $nickname)
                        .textFieldStyle(.roundedBorder)
                }

                if let error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Button {
                    Task { await performAuth() }
                } label: {
                    if isLoading {
                        ProgressView()
                    } else {
                        Text(isRegistering ? "注册" : "登录")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(email.isEmpty || password.isEmpty || isLoading)

                Button(isRegistering ? "已有账号？登录" : "没有账号？注册") {
                    isRegistering.toggle()
                    error = nil
                }
                .font(.subheadline)
            }
        }
        .padding()
    }

    private func performAuth() async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            if isRegistering {
                try await authService.register(email: email, password: password, nickname: nickname.isEmpty ? email.components(separatedBy: "@").first ?? "" : nickname)
            } else {
                try await authService.login(email: email, password: password)
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
