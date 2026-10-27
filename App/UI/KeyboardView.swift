import SwiftUI

/// Types into the TV's focused text box as you type on the iPhone.
struct KeyboardView: View {
    @EnvironmentObject var tv: TV
    @State private var text = ""
    @State private var sent = ""
    @State private var pending: DispatchWorkItem?
    @State private var dropped = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Type on TV").font(.sf(26, .bold)).foregroundColor(.white)
                Text("Select a search box on the TV, then type here.")
                    .font(.sf(14))
                    .foregroundColor(.white.opacity(0.55))
            }

            HStack(spacing: 12) {
                Image(systemName: "text.cursor")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.accent)
                TextField("", text: $text)
                    .textFieldStyle(.plain)
                    .font(.sf(22, .medium))
                    .foregroundColor(.white)
                    .focused($focused)
                    .submitLabel(.search)
                    .disableAutocorrection(true)
                    .noAutocapitalization()
                    .onSubmit {
                        flush()
                        tv.submit()
                        Haptics.press()
                        focused = true
                    }
                    .overlay(alignment: .leading) {
                        if text.isEmpty {
                            Text("Movies, shows, channels…")
                                .font(.sf(22, .medium))
                                .foregroundColor(.white.opacity(0.3))
                                .allowsHitTesting(false)
                        }
                    }
            }
            .padding(.horizontal, 20)
            .frame(height: 66)
            .glass(RoundedRectangle(cornerRadius: 22, style: .continuous))

            HStack(spacing: 10) {
                action("delete.left", "Delete") {
                    if text.isEmpty { tv.type("", deleting: 1) } else { text.removeLast() }
                }
                action("arrow.left.and.right", "Space") { text.append(" ") }
                action("magnifyingglass", "Search", filled: true) {
                    flush()
                    tv.submit()
                }
            }

            Button {
                Haptics.press()
                tv.type("", deleting: max(sent.count, 40))
                sent = ""
                text = ""
            } label: {
                Label("Clear the TV's text box", systemImage: "xmark.circle.fill")
                    .font(.sf(14, .semibold))
                    .foregroundColor(.white.opacity(0.65))
            }
            .buttonStyle(.plain)

            if dropped {
                Label("Only English letters, numbers and symbols reach the TV.", systemImage: "info.circle")
                    .font(.sf(13))
                    .foregroundColor(.warn)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .onChange(of: text) { value in
            let ascii = String(value.unicodeScalars.filter { $0.isASCII }.map(Character.init))
            if ascii != value {
                dropped = true
                text = ascii
                return
            }
            schedule()
        }
        .onAppear { focused = true }
    }

    private func action(_ symbol: String, _ title: String, filled: Bool = false, run: @escaping () -> Void) -> some View {
        Button {
            Haptics.press()
            run()
        } label: {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 18, weight: .semibold))
                Text(title).font(.sf(13, .semibold))
            }
            .foregroundColor(filled ? .black : .white)
            .frame(maxWidth: .infinity)
            .frame(height: 64)
            .background {
                if filled {
                    RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white)
                }
            }
            .glass(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(PressScale())
    }

    /// Sends what changed a moment after typing pauses, so a word goes over as one command.
    private func schedule() {
        pending?.cancel()
        let work = DispatchWorkItem { flush() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    private func flush() {
        pending?.cancel()
        let old = Array(sent)
        let new = Array(text)
        var common = 0
        while common < old.count, common < new.count, old[common] == new[common] { common += 1 }
        let deleting = old.count - common
        let adding = String(new[common...])
        guard deleting > 0 || !adding.isEmpty else { return }
        tv.type(adding, deleting: deleting)
        sent = text
    }
}

extension View {
    @ViewBuilder
    func noAutocapitalization() -> some View {
        #if os(iOS)
        textInputAutocapitalization(.never)
        #else
        self
        #endif
    }
}
