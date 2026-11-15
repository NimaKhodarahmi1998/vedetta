/// The map in plain sentences for VoiceOver: fast movers first, then what blocks the path, then the rest.
enum MapDescription {
    static func text(for engine: GuideEngine) -> String {
        let language = engine.language
        guard engine.isRunning else { return language.text("La guida è in pausa.", "Guidance is paused.") }
        guard engine.isReliable else {
            return InterfaceText.unreliable(engine.reason, in: language) + ". " + language.text("La mappa è ferma.", "The map is frozen.")
        }

        var sentences = engine.sceneItems.filter(\.isFast).map { sentence(for: $0, in: language) }
        if let pathAhead = engine.pathAhead {
            sentences.append(sentence(for: pathAhead, in: language))
        }
        sentences += engine.sceneItems.filter { !$0.isFast }.map { sentence(for: $0, in: language) }
        guard !sentences.isEmpty else { return language.text("Il percorso davanti a te è libero.", "The path ahead is clear.") }
        return sentences.joined(separator: " ")
    }

    private static func sentence(for item: SceneItem, in language: Language) -> String {
        let thing = item.kind.indefiniteName(in: language)
        let place = direction(item.direction, in: language) + ", " + distance(item.distance, in: language)
        let phrase: String
        if item.isFast {
            phrase = thing + language.text(" veloce ", " moving fast ") + place
        } else {
            switch item.state {
                case .hidden: phrase = thing + language.text(item.kind.isFeminine ? " nascosta " : " nascosto ", " hidden ") + place
                case .maybe: phrase = language.text("forse ", "maybe ") + thing + " " + place
                case .sure, .lost, .out: phrase = thing + " " + place
            }
        }
        return phrase.prefix(1).uppercased() + phrase.dropFirst() + "."
    }

    private static func sentence(for pathAhead: PathAhead, in language: Language) -> String {
        let thing = pathAhead.isWall ? language.text("Un muro", "A wall") : language.text("Un ostacolo", "An obstacle")
        let place = direction(.ahead, in: language) + ", " + distance(pathAhead.distance, in: language)
        let opening: String
        switch pathAhead.opening {
            case .none: opening = ""
            case .left: opening = language.text(", con un passaggio a sinistra", ", with an opening on your left")
            case .right: opening = language.text(", con un passaggio a destra", ", with an opening on your right")
        }
        return thing + " " + place + opening + "."
    }

    private static func direction(_ direction: SceneDirection, in language: Language) -> String {
        switch direction {
            case .ahead: language.text("davanti a te", "ahead of you")
            case .left: language.text("sulla sinistra", "on your left")
            case .right: language.text("sulla destra", "on your right")
            case .behind: language.text("dietro di te", "behind you")
        }
    }

    private static func distance(_ metres: Float, in language: Language) -> String {
        guard metres >= 1 else { return language.text("a meno di un metro", "less than a meter away") }
        let rounded = Int(metres.rounded())
        return rounded == 1 ? language.text("a 1 metro", "1 meter away") : language.text("a \(rounded) metri", "\(rounded) meters away")
    }
}
