/// Short on purpose: the user is walking.
nonisolated enum SpokenLine {
    static func side(isLeft: Bool, in language: Language) -> String {
        isLeft ? language.text("sinistra", "left") : language.text("destra", "right")
    }

    static func start(in language: Language) -> String {
        language.text("Guida attiva. Vedo solo davanti.", "Guidance on. I only see ahead.")
    }

    static func ahead(_ kind: ObjectKind, isClose: Bool, in language: Language) -> String {
        let name = kind.name(in: language)
        switch language {
            case .italian: return isClose ? "\(name) davanti, vicin\(ending(for: kind))" : "\(name) davanti"
            case .english: return isClose ? "\(name) ahead, close" : "\(name) ahead"
        }
    }

    static func hidden(_ kind: ObjectKind, isLeft: Bool, in language: Language) -> String {
        let name = kind.name(in: language)
        let direction = side(isLeft: isLeft, in: language)
        switch language {
            case .italian: return "\(name) nascost\(ending(for: kind)), a \(direction)"
            case .english: return "\(name) hidden, on your \(direction)"
        }
    }

    static func back(_ kind: ObjectKind, isLeft: Bool, in language: Language) -> String {
        let name = kind.name(in: language)
        let direction = side(isLeft: isLeft, in: language)
        switch language {
            case .italian: return "\(name) riappars\(ending(for: kind)), a \(direction)"
            case .english: return "\(name) back in view, on your \(direction)"
        }
    }

    static func lost(_ kind: ObjectKind, in language: Language) -> String {
        let name = kind.name(in: language)
        switch language {
            case .italian: return "\(name) pers\(ending(for: kind)) di vista"
            case .english: return "Lost sight of the \(name.lowercased())"
        }
    }

    /// «Bici veloce da sinistra!»: what is coming and from where. «Veloce a sinistra» sounded like an order.
    static func fast(_ kind: ObjectKind, isLeft: Bool, in language: Language) -> String {
        let name = kind.name(in: language)
        let direction = side(isLeft: isLeft, in: language)
        switch language {
            case .italian: return "\(name) veloce da \(direction)!"
            case .english: return "Fast \(name.lowercased()) from the \(direction)!"
        }
    }

    static func unreliable(_ reason: UnreliableReason, in language: Language) -> String {
        language.text("Guida non affidabile: ", "Guidance unreliable: ") + reason.text(in: language)
    }

    static func reliable(withTorch: Bool, in language: Language) -> String {
        withTorch
            ? language.text("Guida di nuovo attiva, con la torcia: vedo solo vicino", "Guidance back on, with the torch: I only see close by")
            : language.text("Guida di nuovo attiva", "Guidance back on")
    }

    static func obstacle(in language: Language) -> String {
        language.text("Ostacolo davanti", "Obstacle ahead")
    }

    static func wall(isClose: Bool, opening: PathOpening, in language: Language) -> String {
        let line = isClose
            ? language.text("Muro davanti, vicino", "Wall ahead, close")
            : language.text("Muro davanti", "Wall ahead")
        guard opening != .none else { return line }

        return line + language.text(". Passaggio a ", ". Opening on your ") + side(isLeft: opening == .left, in: language)
    }

    static func torchOn(in language: Language) -> String {
        language.text("Provo con la torcia", "Trying the torch")
    }

    static func torchOff(in language: Language) -> String {
        language.text("Torna la luce: spengo la torcia.", "Light is back: torch off.")
    }

    /// Blind walkers count paces: about 0.7 m each.
    static func paces(_ distance: Float) -> Int { max(1, Int((distance / 0.7).rounded())) }

    /// A drop seen from far away hides its treads: it may be stairs going down or a ledge, so it says both.
    static func floorName(_ kind: FloorKind, in language: Language) -> String {
        switch kind {
            case .stepUp: language.text("Gradino in salita", "Step up")
            case .stepDown: language.text("Gradino in discesa", "Step down")
            case .stairsUp: language.text("Scale in salita", "Stairs up")
            case .stairsDown: language.text("Scale in discesa", "Stairs down")
            case .dropOff: language.text("Attenzione: scale o dislivello in discesa", "Careful: stairs or a drop going down")
            case .lowObstacle: language.text("Ostacolo basso", "Low obstacle")
        }
    }

    /// Close by, in the walking path: in paces.
    static func floor(_ kind: FloorKind, distance: Float, in language: Language) -> String {
        let name = floorName(kind, in: language)
        if distance < 0.9 { return name + language.text(", proprio davanti", ", right in front") }
        let count = paces(distance)
        switch language {
            // «tra 2 passi»: «a due passi» means "very close" in Italian.
            case .italian: return name + ", tra \(count) pass\(count == 1 ? "o" : "i")"
            case .english: return name + ", \(count) pace\(count == 1 ? "" : "s") ahead"
        }
    }

    /// Seen early (up to 30 m): in metres, with the side when it isn't straight ahead.
    /// side: +1 = on the left, -1 = on the right, 0 = ahead.
    static func floorFar(_ kind: FloorKind, distance: Float, side: Int, in language: Language) -> String {
        let name = floorName(kind, in: language)
        // Far away the distance is rough: whole metres up to 10 m, then steps of 2 m, then 5 m.
        let step: Float = distance <= 10 ? 1 : (distance <= 20 ? 2 : 5)
        let metres = max(1, Int((distance / step).rounded() * step))
        switch language {
            case .italian:
                let line = "\(name) a \(metres) metr\(metres == 1 ? "o" : "i")"
                return side == 0 ? line : line + ", a " + Self.side(isLeft: side > 0, in: language)
            case .english:
                let line = "\(name), \(metres) metre\(metres == 1 ? "" : "s")"
                return side == 0 ? line + " ahead" : line + ", on your " + Self.side(isLeft: side > 0, in: language)
        }
    }

    /// Silence must never sound like "clear": where the floor visibly ends, it says so.
    static func floorEnds(in language: Language) -> String {
        language.text("Attenzione: non vedo il pavimento", "Careful: I can't see the floor ahead")
    }

    /// A hint from the picture as a whole, so it says «possibili»: the floor reader still has to see the steps.
    static func stairsLikely(in language: Language) -> String {
        language.text("Possibili scale davanti", "Possible stairs ahead")
    }

    static func markAdded(in language: Language) -> String {
        language.text("Ostacolo segnato", "Obstacle marked")
    }

    static func markRemoved(in language: Language) -> String {
        language.text("Segno tolto", "Mark removed")
    }

    /// A marked obstacle ahead, in paces like the floor lines.
    static func markAhead(distance: Float, in language: Language) -> String {
        if distance < 0.9 { return language.text("Ostacolo segnato, proprio davanti", "Marked obstacle, right in front") }
        let count = paces(distance)
        switch language {
            case .italian: return "Ostacolo segnato, tra \(count) pass\(count == 1 ? "o" : "i")"
            case .english: return "Marked obstacle, \(count) pace\(count == 1 ? "" : "s") ahead"
        }
    }

    static func placeRecognized(marks: Int, in language: Language) -> String {
        switch language {
            case .italian: return "Posto riconosciuto: \(marks) " + (marks == 1 ? "ostacolo segnato" : "ostacoli segnati")
            case .english: return "Place recognised: \(marks) marked obstacle" + (marks == 1 ? "" : "s")
        }
    }

    static func placeNotRecognized(in language: Language) -> String {
        language.text("Posto non riconosciuto: i segni salvati non sono attivi", "Place not recognised: saved marks are off")
    }

    static func crowd(in language: Language) -> String {
        language.text("Molta gente davanti", "Crowded ahead")
    }

    static func leftApp(in language: Language) -> String {
        language.text(
            "Sei uscito da Vedetta e la guida è in pausa. Per tornare, di': Ehi Siri, torna a Vedetta.",
            "You left Vedetta and guidance is paused. To go back, say: Hey Siri, back to Vedetta."
        )
    }

    private static func ending(for kind: ObjectKind) -> String {
        kind.isFeminine ? "a" : "o"
    }
}
