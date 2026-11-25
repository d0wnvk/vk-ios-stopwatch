import XCTest
@testable import stopwatch

final class SportTrackerCellCatalogTests: XCTestCase {
    func testDefinitionsHaveUniqueValidCellNumbers() {
        let numbers = SportTrackerCellCatalog.definitions.map(\.number)

        XCTAssertEqual(Set(numbers).count, numbers.count)
        XCTAssertTrue(numbers.allSatisfy { 1...48 ~= $0 })
    }

    func testTappableCellsComeFromDefinitions() {
        let expected: Set<Int> = [
            10, 11, 12,
            14, 15, 16,
            18, 19, 20,
            38, 39, 40,
            42, 43, 44,
            46, 47, 48,
        ]

        XCTAssertEqual(SportTrackerCellCatalog.tappableCellNumbers, expected)
        XCTAssertEqual(SportTrackerModel.tappableCellNumbers, expected)
    }

    func testDatedCellsHaveLabelsAndExpectedSequence() {
        XCTAssertEqual(
            SportTrackerCellCatalog.datedCellSequence,
            [25, 29, 26, 30, 27, 31, 28, 32]
        )

        for number in SportTrackerCellCatalog.datedCellSequence {
            XCTAssertNotNil(SportTrackerCellCatalog.definition(for: number)?.datedLabel)
        }
    }

    func testPreviewCellsAreTappableAndImagesHaveUniqueAssets() {
        let previewDefinitions = SportTrackerCellCatalog.definitions.filter {
            $0.exercisePreview != nil
        }

        XCTAssertTrue(previewDefinitions.allSatisfy(\.isTappable))

        let assetNames = previewDefinitions.flatMap {
            $0.exercisePreview?.images.map(\.assetName) ?? []
        }
        XCTAssertEqual(Set(assetNames).count, assetNames.count)
    }

    func testDisplayedRowsProduceValidCellNumbers() {
        let displayedCellNumbers = SportTrackerCellCatalog.displayedRows.flatMap { row in
            (0..<4).map { row * 4 + $0 + 1 }
        }

        XCTAssertTrue(displayedCellNumbers.allSatisfy { 1...48 ~= $0 })
        XCTAssertTrue(
            SportTrackerCellCatalog.definitions.allSatisfy {
                displayedCellNumbers.contains($0.number)
            }
        )
    }
}
