import SwiftUI

struct SVGShape: Shape {
    let data: String
    let box: CGSize

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width / box.width, rect.height / box.height)
        let x = rect.midX - box.width * scale / 2
        let y = rect.midY - box.height * scale / 2
        return Path(svg: data).applying(CGAffineTransform(scaleX: scale, y: scale).concatenating(CGAffineTransform(translationX: x, y: y)))
    }
}

enum BrandMarks {
    static let google: [(String, Color)] = [
        ("M24 9.5c3.54 0 6.71 1.22 9.21 3.6l6.85-6.85C35.9 2.38 30.47 0 24 0 14.62 0 6.51 5.38 2.56 13.22l7.98 6.19C12.43 13.72 17.74 9.5 24 9.5z", Color(hex: 0xEA4335)),
        ("M46.98 24.55c0-1.57-.15-3.09-.38-4.55H24v9.02h12.94c-.58 2.96-2.26 5.48-4.78 7.18l7.73 6c4.51-4.18 7.09-10.36 7.09-17.65z", Color(hex: 0x4285F4)),
        ("M10.53 28.59c-.48-1.45-.76-2.99-.76-4.59s.27-3.14.76-4.59l-7.98-6.19C.92 16.46 0 20.12 0 24c0 3.88.92 7.54 2.56 10.78l7.97-6.19z", Color(hex: 0xFBBC05)),
        ("M24 48c6.48 0 11.93-2.13 15.89-5.81l-7.73-6c-2.15 1.45-4.92 2.3-8.16 2.3-6.26 0-11.57-4.22-13.47-9.91l-7.98 6.19C6.51 42.62 14.62 48 24 48z", Color(hex: 0x34A853)),
    ]
}

struct AppleMark: View {
    var color: Color
    var size: CGFloat

    var body: some View {
        Image(systemName: "applelogo")
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(color)
    }
}

struct GoogleMark: View {
    var body: some View {
        ZStack {
            ForEach(Array(BrandMarks.google.enumerated()), id: \.offset) { _, part in
                SVGShape(data: part.0, box: CGSize(width: 48, height: 48)).fill(part.1)
            }
        }
    }
}

struct ProviderButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(Motion.press, value: configuration.isPressed)
    }
}

// Apple and Google ask for their own button looks, black or white with the original marks.
struct AppleSignInButton: View {
    let busy: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .circular)
        let foreground: Color = scheme == .dark ? .black : .white
        Button(action: action) {
            HStack(spacing: 10) {
                if busy {
                    ProgressView().tint(foreground)
                } else {
                    AppleMark(color: foreground, size: 19)
                }
                Text("Continue with Apple")
                    .font(.app(.golos, 17, weight: 600))
            }
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(shape.fill(scheme == .dark ? Color.white : Color.black))
            .contentShape(shape)
        }
        .buttonStyle(ProviderButtonStyle())
    }
}

struct GoogleSignInButton: View {
    let busy: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .circular)
        let dark = scheme == .dark
        Button(action: action) {
            HStack(spacing: 10) {
                if busy {
                    ProgressView()
                } else {
                    GoogleMark()
                        .frame(width: 20, height: 20)
                }
                Text("Continue with Google")
                    .font(.app(.golos, 17, weight: 600))
            }
            .foregroundStyle(dark ? Color(hex: 0xE3E3E3) : Color(hex: 0x1F1F1F))
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(shape.fill(dark ? Color(hex: 0x131314) : .white))
            .overlay(shape.strokeBorder(dark ? Color(hex: 0x8E918F) : Color(hex: 0x747775), lineWidth: 1))
            .contentShape(shape)
        }
        .buttonStyle(ProviderButtonStyle())
    }
}

struct AuthField<Field: Hashable>: View {
    enum Kind {
        case email
        case password
        case newPassword
        case code
    }

    let title: LocalizedStringKey
    @Binding var text: String
    let kind: Kind
    var focus: FocusState<Field?>.Binding
    let field: Field
    var submit: () -> Void = {}
    @State private var revealed = false

    private var hidesText: Bool {
        kind == .password || kind == .newPassword
    }

    private var secure: Bool {
        hidesText && !revealed
    }

    private var keyboard: UIKeyboardType {
        switch kind {
        case .email: .emailAddress
        case .code: .numberPad
        case .password, .newPassword: .asciiCapable
        }
    }

    private var content: UITextContentType {
        switch kind {
        case .email: .username
        case .code: .oneTimeCode
        case .newPassword: .newPassword
        case .password: .password
        }
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .circular)
        let focused = focus.wrappedValue == field
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: title)
            HStack(spacing: 0) {
                Group {
                    if secure {
                        SecureField("", text: $text)
                    } else {
                        TextField("", text: $text)
                    }
                }
                .font(.app(.golos, 17))
                .tracking(kind == .code ? 6 : (kind == .email ? 0 : 2))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(keyboard)
                .textContentType(content)
                .submitLabel(kind == .email ? .next : .go)
                .onSubmit(submit)
                .focused(focus, equals: field)
                .tint(Palette.accent)
                .padding(.leading, 16)
                .padding(.trailing, hidesText ? 0 : 16)
                if hidesText {
                    Button {
                        revealed.toggle()
                        focus.wrappedValue = field
                    } label: {
                        Glyph(paths: revealed ? Icons.eye : Icons.eyeOff, size: 20, lineWidth: 2, color: Palette.secondary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(revealed ? LocalizedStringKey("Hide password") : LocalizedStringKey("Show password")))
                    .padding(.trailing, 6)
                }
            }
            .frame(height: 56)
            .background {
                shape
                    .fill(Palette.well)
                    .insetShadow(shape, Palette.wellShadow, blur: 2, y: 1)
            }
            .overlay {
                shape.strokeBorder(focused ? Palette.accent : Palette.wellBorder, lineWidth: focused ? 2 : 1)
            }
            .animation(Motion.small, value: focused)
        }
    }
}

struct FormNote: View {
    let text: LocalizedStringKey

    var body: some View {
        Text(text)
            .font(.app(.golos, 13))
            .lineHeight(18, .golos, 13)
            .foregroundStyle(Palette.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct FormProblem: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(.app(.golos, 14, weight: 500))
            .foregroundStyle(Palette.urgentText)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

extension String {
    var looksLikeEmail: Bool {
        let parts = trimmingCharacters(in: .whitespaces).split(separator: "@")
        return parts.count == 2 && !parts[0].isEmpty && parts[1].contains(".") && !parts[1].hasSuffix(".")
    }
}
