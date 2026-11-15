nonisolated enum ObjectKind {
    case person, bike, motorbike, car, bus, truck, dog, animal, thing

    init?(detectorLabel: String) {
        switch detectorLabel {
            case "person": self = .person
            case "bicycle": self = .bike
            case "motorcycle": self = .motorbike
            case "car": self = .car
            case "bus": self = .bus
            case "truck": self = .truck
            case "dog": self = .dog
            case "cat", "horse", "sheep", "cow": self = .animal
            // Furniture isn't named, to avoid overload: the 3D map reports it as an obstacle
            default: return nil
        }
    }

    /// Detections only match tracks in the same group.
    var matchGroup: Int {
        switch self {
            case .person: 0
            case .bike, .motorbike: 1
            case .car, .bus, .truck: 2
            case .dog, .animal: 3
            case .thing: 4
        }
    }

    var isMover: Bool { self != .thing }

    /// In meters, for ranging from the box height when the ground can't be found.
    var typicalHeight: Float {
        switch self {
            case .person: 1.7
            case .bike: 1.65
            case .motorbike: 1.5
            case .car: 1.5
            case .bus, .truck: 3.0
            case .dog: 0.6
            case .animal: 1.2
            case .thing: 0.9
        }
    }

    /// Italian grammatical gender, as in nascosta or nascosto.
    var isFeminine: Bool {
        switch self {
            case .person, .bike, .motorbike, .car: true
            case .bus, .truck, .dog, .animal, .thing: false
        }
    }

    func name(in language: Language) -> String {
        switch self {
            case .person: language.text("Persona", "Person")
            case .bike: language.text("Bici", "Bike")
            case .motorbike: language.text("Moto", "Motorbike")
            case .car: language.text("Auto", "Car")
            case .bus: language.text("Autobus", "Bus")
            case .truck: language.text("Camion", "Truck")
            case .dog: language.text("Cane", "Dog")
            case .animal: language.text("Animale", "Animal")
            case .thing: language.text("Ostacolo", "Obstacle")
        }
    }

    /// With its article, for full sentences: "una persona", "an obstacle".
    func indefiniteName(in language: Language) -> String {
        switch self {
            case .person: language.text("una persona", "a person")
            case .bike: language.text("una bici", "a bike")
            case .motorbike: language.text("una moto", "a motorbike")
            case .car: language.text("un’auto", "a car")
            case .bus: language.text("un autobus", "a bus")
            case .truck: language.text("un camion", "a truck")
            case .dog: language.text("un cane", "a dog")
            case .animal: language.text("un animale", "an animal")
            case .thing: language.text("un ostacolo", "an obstacle")
        }
    }
}
