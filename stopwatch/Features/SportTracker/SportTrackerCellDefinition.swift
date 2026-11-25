import Foundation

struct SportTrackerCellDefinition {
    let number: Int
    let label: String
    let labelLines: [String]
    let labelFontSize: Double?
    let isTappable: Bool
    let exercisePreview: ExercisePreview?
    let datedLabel: String?
    let legPalmDirection: String?

    init(
        number: Int,
        label: String = "",
        labelLines: [String]? = nil,
        labelFontSize: Double? = nil,
        isTappable: Bool = false,
        previewImages: [ExercisePreviewImage] = [],
        datedLabel: String? = nil,
        legPalmDirection: String? = nil
    ) {
        self.number = number
        self.label = label
        self.labelLines = labelLines ?? (label.isEmpty ? [] : [label])
        self.labelFontSize = labelFontSize
        self.isTappable = isTappable
        exercisePreview = previewImages.isEmpty ? nil : ExercisePreview(images: previewImages)
        self.datedLabel = datedLabel
        self.legPalmDirection = legPalmDirection
    }
}

struct ExercisePreview {
    let images: [ExercisePreviewImage]
}

struct ExercisePreviewImage: Identifiable {
    var id: String { assetName }
    let assetName: String
    let fileName: String
}

enum SportTrackerCellCatalog {
    static let displayedRows = [0, 1, 2, 3, 4, 6, 7, 9, 10, 11]
    static let datedCellSequence = [25, 29, 26, 30, 27, 31, 28, 32]

    static let definitions: [SportTrackerCellDefinition] = [
        .init(number: 2, label: "Up"),
        .init(number: 3, label: "Middle"),
        .init(number: 4, label: "Down"),

        .init(number: 9, label: "спина"),
        .init(
            number: 10,
            label: "подтягивания",
            labelLines: ["подтяги-", "вания"],
            isTappable: true,
            previewImages: [
                .init(assetName: "up-back-01", fileName: "up-back-01.jpg"),
                .init(assetName: "up-back-02", fileName: "up-back-02.jpg"),
            ]
        ),
        .init(
            number: 11,
            label: "сверху под 45гр",
            labelLines: ["сверху", "под 45гр"],
            isTappable: true,
            previewImages: [
                .init(assetName: "middle-back-45gr-01", fileName: "middle-back-45gr-01.jpg")
            ]
        ),
        .init(
            number: 12,
            label: "сидя узкий хват",
            labelLines: ["сидя", "узкий", "хват"],
            labelFontSize: 21.28896,
            isTappable: true,
            previewImages: [.init(assetName: "down-back-01", fileName: "down-back-01.jpg")]
        ),

        .init(number: 13, label: "бицепс"),
        .init(
            number: 14,
            label: "молотковый хват",
            labelLines: ["молотко-", "вый хват"],
            isTappable: true
        ),
        .init(
            number: 15,
            label: "сидя снизу-вверх",
            labelLines: ["сидя", "снизу-", "вверх"],
            labelFontSize: 21.28896,
            isTappable: true,
            previewImages: [.init(assetName: "middle-biceps-01", fileName: "middle-biceps-01.jpg")]
        ),
        .init(number: 16, label: "z-гриф", isTappable: true),

        .init(number: 17, label: "ноги, ладонь вниз", legPalmDirection: "вниз"),
        .init(
            number: 18,
            label: "плечи вверх",
            labelLines: ["плечи", "вверх"],
            isTappable: true
        ),
        .init(number: 19, label: "развод", isTappable: true),
        .init(number: 20, label: "свод", isTappable: true),

        .init(number: 25, datedLabel: "5L"),
        .init(number: 26, datedLabel: "5H"),
        .init(number: 27, datedLabel: "6L"),
        .init(number: 28, datedLabel: "6H"),
        .init(number: 29, datedLabel: "5L"),
        .init(number: 30, datedLabel: "5H"),
        .init(number: 31, datedLabel: "6L"),
        .init(number: 32, datedLabel: "6H"),

        .init(number: 37, label: "грудь"),
        .init(
            number: 38,
            label: "вверх",
            isTappable: true,
            previewImages: [
                .init(assetName: "up-chest-01", fileName: "up-chest-01.jpg"),
                .init(assetName: "up-chest-02", fileName: "up-chest-02.jpg"),
            ]
        ),
        .init(
            number: 39,
            label: "сводящие, не толкающие",
            labelLines: ["сводящие,", "не тол-", "кающие"],
            labelFontSize: 18.634,
            isTappable: true,
            previewImages: [.init(assetName: "grud-middle", fileName: "grud-middle.JPG")]
        ),
        .init(
            number: 40,
            label: "отжим на брусьях",
            labelLines: ["отжим на", "брусьях"],
            isTappable: true,
            previewImages: [.init(assetName: "down-chest-01", fileName: "down-chest-01.jpg")]
        ),

        .init(number: 41, label: "трицепс"),
        .init(number: 42, label: "вверх", isTappable: true),
        .init(
            number: 43,
            label: "из положения лежа на спине",
            labelLines: ["из положе-", "ния лежа", "на спине"],
            labelFontSize: 18.634,
            isTappable: true,
            previewImages: [.init(assetName: "triceps-leza", fileName: "triceps-leza.JPG")]
        ),
        .init(number: 44, label: "вниз", isTappable: true),

        .init(number: 45, label: "ноги, ладонь вверх", legPalmDirection: "вверх"),
        .init(number: 46, label: "вперед", isTappable: true),
        .init(number: 47, label: "приседы", isTappable: true),
        .init(number: 48, label: "назад", isTappable: true),
    ]

    private static let definitionsByNumber = Dictionary(
        uniqueKeysWithValues: definitions.map { ($0.number, $0) }
    )

    static let tappableCellNumbers = Set(
        definitions.lazy.filter(\.isTappable).map(\.number)
    )

    static let datedCellNumbers = Set(datedCellSequence)

    static func definition(for number: Int) -> SportTrackerCellDefinition? {
        definitionsByNumber[number]
    }
}
