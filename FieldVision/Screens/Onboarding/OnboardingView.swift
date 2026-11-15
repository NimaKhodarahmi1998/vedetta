import SwiftUI

/// The first thing a new walker meets, and again from «Come funziona»: what Vedetta does, how to hold the phone,
/// the four sounds to learn by ear, the long press, and the honest promise. Without VoiceOver each page is spoken
/// aloud; with VoiceOver, VoiceOver reads it.
struct OnboardingView: View {
    @Environment(GuideEngine.self) private var engine
    @Environment(\.accessibilityVoiceOverEnabled) private var isVoiceOverOn
    let onFinish: (_ startsGuidance: Bool) -> Void
    @State private var page = OnboardingPage.welcome

    var body: some View {
        let language = engine.language
        let isLast = page == OnboardingPage.allCases.last
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Text(OnboardingText.step(page.rawValue + 1, of: OnboardingPage.allCases.count, in: language))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                if !isLast {
                    Button(OnboardingText.skip(in: language)) { onFinish(false) }
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Image(systemName: page.symbol)
                        .font(.system(size: 56))
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                    Text(page.title(in: language))
                        .font(.largeTitle.bold())
                        .accessibilityAddTraits(.isHeader)
                    Text(page.body(in: language))
                        .font(.title3)
                    if page == .sounds {
                        ForEach(OnboardingText.samples(in: language)) { sample in
                            SoundButton(sample: sample)
                        }
                    }
                    if let note = page.note(in: language) {
                        Text(note)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                if page != .welcome {
                    Button(OnboardingText.back(in: language)) { move(by: -1) }
                        .glassButton()
                }
                Spacer()
                Button(isLast ? OnboardingText.begin(in: language) : OnboardingText.next(in: language)) {
                    if isLast { onFinish(true) } else { move(by: 1) }
                }
                .glassButton(isProminent: true)
            }
            .controlSize(.large)
        }
        .padding(24)
        .background(Color(.systemGroupedBackground))
        .onChange(of: page, initial: true) { _, page in
            if !isVoiceOverOn { engine.speak(page.spoken(in: engine.language)) }
        }
    }

    private func move(by step: Int) {
        if let next = OnboardingPage(rawValue: page.rawValue + step) { page = next }
    }
}

/// One sound to learn: plays it, then (without VoiceOver) says what it means.
private struct SoundButton: View {
    @Environment(GuideEngine.self) private var engine
    @Environment(\.accessibilityVoiceOverEnabled) private var isVoiceOverOn
    let sample: SoundSample

    var body: some View {
        Button {
            engine.preview(sample.cue)
            guard !isVoiceOverOn else { return }
            Task {
                try? await Task.sleep(for: .milliseconds(900))
                engine.speak(sample.meaning)
            }
        } label: {
            HStack(spacing: 16) {
                Image(systemName: "play.circle.fill")
                    .font(.title)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 4) {
                    Text(sample.name).font(.headline)
                    Text(sample.meaning).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.regularMaterial, in: .rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(sample.name): \(sample.meaning)")
        .accessibilityHint(OnboardingText.playHint(in: engine.language))
        .accessibilityAddTraits(.isButton)
    }
}

struct SoundSample: Identifiable {
    let cue: Cue
    let name: String
    let meaning: String
    var id: String { name }
}

enum OnboardingPage: Int, CaseIterable {
    case welcome, hold, sounds, mark, ready

    var symbol: String {
        switch self {
            case .welcome: "figure.walk"
            case .hold: "iphone"
            case .sounds: "speaker.wave.3.fill"
            case .mark: "hand.tap.fill"
            case .ready: "checkmark.circle.fill"
        }
    }

    func title(in language: Language) -> String {
        switch self {
            case .welcome: language.text("Benvenuto in Vedetta", "Welcome to Vedetta")
            case .hold: language.text("Come tenere il telefono", "How to hold the phone")
            case .sounds: language.text("Ascolta i suoni", "Learn the sounds")
            case .mark: language.text("Segna un ostacolo", "Mark an obstacle")
            case .ready: language.text("Pronto", "Ready")
        }
    }

    func body(in language: Language) -> String {
        switch self {
            case .welcome: language.text(
                "Mentre cammini ti dice cosa c’è davanti: persone, ostacoli, muri e gradini. Funziona senza rete e tutto resta sul telefono. Non sostituisce il bastone o il cane: li affianca.",
                "While you walk, it tells you what is ahead: people, obstacles, walls and steps. It works offline and everything stays on the phone. It does not replace your cane or dog: it works alongside them."
            )
            case .hold: language.text(
                "All’altezza del petto, con la fotocamera in avanti e un po’ verso il basso. Una fascia da petto ti lascia le mani libere.",
                "At chest height, camera facing forward and a little down. A chest strap keeps your hands free."
            )
            case .sounds: language.text("Tocca ogni suono per sentirlo.", "Tap each sound to hear it.")
            case .mark: language.text(
                "Tieni premuto sullo schermo per segnare l’ostacolo che hai davanti: quando ci ripassi, nello stesso giro, Vedetta te lo ricorda. Tieni premuto di nuovo sullo stesso punto per toglierlo.",
                "Press and hold the screen to mark the obstacle in front of you: when you pass it again on the same walk, Vedetta reminds you. Press and hold on the same spot again to remove it."
            )
            case .ready: language.text(
                "Quando non posso fidarmi di ciò che vedo, te lo dico. Ora puoi iniziare.",
                "When I can’t trust what I see, I tell you. You can start now."
            )
        }
    }

    func note(in language: Language) -> String? {
        switch self {
            case .sounds: language.text("Se il tic si ferma, la strada non è verificata.", "If the tick stops, the way is not checked.")
            case .mark: language.text("Con VoiceOver, usa l’azione «Segna ostacolo».", "With VoiceOver, use the «Mark obstacle» action.")
            default: nil
        }
    }

    func spoken(in language: Language) -> String {
        [title(in: language) + ".", body(in: language), note(in: language)].compactMap { $0 }.joined(separator: " ")
    }
}

enum OnboardingText {
    static func step(_ number: Int, of count: Int, in language: Language) -> String {
        language.text("Passo \(number) di \(count)", "Step \(number) of \(count)")
    }

    static func skip(in language: Language) -> String { language.text("Salta", "Skip") }
    static func back(in language: Language) -> String { language.text("Indietro", "Back") }
    static func next(in language: Language) -> String { language.text("Avanti", "Next") }
    static func begin(in language: Language) -> String { language.text("Inizia la guida", "Start guidance") }
    static func playHint(in language: Language) -> String { language.text("Lo fa sentire", "Plays it") }

    static func samples(in language: Language) -> [SoundSample] {
        [
            SoundSample(cue: .tick, name: language.text("Tic, ogni 2 secondi", "Tick, every 2 seconds"),
                        meaning: language.text("Vedo la strada", "I can see the way")),
            SoundSample(cue: .knock, name: language.text("Un colpo", "One knock"),
                        meaning: language.text("Qualcosa davanti", "Something ahead")),
            SoundSample(cue: .fast, name: language.text("Due impulsi forti", "Two strong pulses"),
                        meaning: language.text("Pericolo: qualcosa di veloce, o il pavimento che finisce", "Danger: something fast, or the floor ending")),
            SoundSample(cue: .long, name: language.text("Lungo-lungo", "Long-long"),
                        meaning: language.text("Non mi fido di ciò che vedo: rallenta e usa il bastone", "I can’t trust what I see: slow down and use your cane")),
        ]
    }
}
