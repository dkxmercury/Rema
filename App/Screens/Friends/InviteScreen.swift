import CoreImage.CIFilterBuiltins
import RemaCore
import SwiftUI

struct InviteScreen: View {
    let onClose: () -> Void

    @State private var service = SharedService.shared
    @State private var code: String?
    @State private var problem: String?
    @State private var unconfirmed = false
    @State private var name = ""
    @State private var copied = false
    @FocusState private var nameFocused: Bool

    private var link: URL? {
        code.map(SharedService.link)
    }

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    qrPanel
                        .frame(maxWidth: .infinity)
                        .padding(.top, 18)
                    Note("A friend points the camera or opens the link. The invitation works once, for a day, and can be withdrawn.")
                        .padding(.top, 16)
                    PanelList {
                        Button(action: copy) {
                            HStack(spacing: 12) {
                                Glyph(paths: Icons.link, size: 20, lineWidth: 2, color: Palette.text)
                                Text("Link")
                                    .font(.app(.golos, 16, weight: 500))
                                Spacer(minLength: 8)
                                Text(verbatim: copied ? String(localized: "Copied", bundle: .app, locale: .app) : link.map { $0.absoluteString.replacingOccurrences(of: "https://", with: "") } ?? "…")
                                    .font(.app(.golos, 14))
                                    .foregroundStyle(Palette.secondary)
                                    .lineLimit(1)
                            }
                            .frame(minHeight: 52)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(RowPressStyle())
                        .disabled(link == nil)
                        Hairline()
                        HStack(spacing: 12) {
                            Glyph(paths: Icons.pen, size: 20, lineWidth: 2, color: Palette.text)
                            Text("What you will call them")
                                .font(.app(.golos, 16, weight: 500))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .layoutPriority(1)
                            TextField(text: $name, prompt: Text("Name").foregroundColor(Palette.secondary)) {
                                Text("Name")
                            }
                            .font(.app(.golos, 14))
                            .multilineTextAlignment(.trailing)
                            .focused($nameFocused)
                            .submitLabel(.done)
                            .onChange(of: name) { _, value in
                                if let code {
                                    service.setPendingName(code, value)
                                }
                            }
                        }
                        .frame(minHeight: 52)
                    }
                    .padding(.top, 12)
                    Note("Rema does not look people up by email or phone number.")
                        .padding(.top, 10)
                    if unconfirmed {
                        ConfirmEmailNote()
                            .padding(.top, 10)
                    } else if let problem {
                        Note(verbatim: problem)
                            .padding(.top, 10)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .pinnedHeader {
                ScreenHeader(title: "Invite to Rema", leading: .close, action: onClose)
            }
            if let link {
                ShareLink(item: link, message: Text("Let's share reminders in Rema")) {
                    Text("Share the link")
                }
                .simultaneousGesture(TapGesture().onEnded {
                    if let code {
                        service.handedOut(code)
                    }
                })
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, 18)
                .padding(.bottom, 28)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .ignoresSafeArea(.container, edges: .bottom)
            }
        }
        .foregroundStyle(Palette.text)
        .task { await create() }
    }

    private var qrPanel: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .circular)
                .fill(Color.white)
            if let link, let image = Self.qr(link.absoluteString) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .padding(18)
                    .accessibilityLabel(Text("Invitation code"))
            } else if problem == nil && !unconfirmed {
                ProgressView()
            }
        }
        .frame(width: 210, height: 210)
        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
    }

    private func create() async {
        guard code == nil else { return }
        do {
            let created = try await service.createInvite(calling: name)
            // A name typed while the code was on its way would otherwise be lost.
            if !name.isEmpty {
                service.setPendingName(created.code, name)
            }
            withAnimation(Motion.standard) { code = created.code }
        } catch let failure as Backend.Failure {
            unconfirmed = failure.needsConfirmedEmail
            problem = failure == .conflict("invite_limit") ? String(localized: "Too many invitations, try again later.", bundle: .app, locale: .app) : failure.friendsMessage
        } catch {
            problem = Backend.Failure.server.message
        }
    }

    private func copy() {
        guard let link, let code else { return }
        service.handedOut(code)
        UIPasteboard.general.url = link
        Feedback.play(.select)
        withAnimation(Motion.standard) { copied = true }
    }

    // Dark modules on white whatever the theme: cameras read an inverted code badly.
    static func qr(_ text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
              let image = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: image)
    }
}
