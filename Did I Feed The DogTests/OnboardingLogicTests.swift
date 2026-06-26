import XCTest
@testable import Did_I_Feed_The_Dog

final class OnboardingLogicTests: XCTestCase {

    // MARK: dogNamesToInsert

    func testReturningUserInsertsNothing() {
        // Dogs already exist (synced from iCloud or local) → onboarding adds no dogs,
        // even if the user typed something during the cold-start race.
        XCTAssertEqual(
            OnboardingLogic.dogNamesToInsert(typed: ["Buster"], existingDogCount: 1, isPro: false),
            [])
        XCTAssertEqual(
            OnboardingLogic.dogNamesToInsert(typed: ["Buster", "Max"], existingDogCount: 2, isPro: true),
            [])
    }

    func testNewFreeUserCappedToOneDog() {
        XCTAssertEqual(
            OnboardingLogic.dogNamesToInsert(typed: ["Buster", "Max"], existingDogCount: 0, isPro: false),
            ["Buster"])
    }

    func testNewProUserGetsAllDogsDedupedCaseInsensitively() {
        XCTAssertEqual(
            OnboardingLogic.dogNamesToInsert(typed: ["Buster", "Max", "buster"], existingDogCount: 0, isPro: true),
            ["Buster", "Max"])
    }

    func testEmptyAndWhitespaceNamesSkipped() {
        XCTAssertEqual(
            OnboardingLogic.dogNamesToInsert(typed: ["  ", "Rex", ""], existingDogCount: 0, isPro: true),
            ["Rex"])
    }

    func testTrimsWhitespace() {
        XCTAssertEqual(
            OnboardingLogic.dogNamesToInsert(typed: ["  Buster  "], existingDogCount: 0, isPro: true),
            ["Buster"])
    }

    // MARK: canLeaveAddDogStep

    func testReturningUserCanAlwaysContinue() {
        // Name is optional for returning users — they can advance without typing a dog.
        XCTAssertTrue(OnboardingLogic.canLeaveAddDogStep(hasExistingDogs: true, hasTypedDogName: false))
    }

    func testNewUserMustTypeADogName() {
        XCTAssertFalse(OnboardingLogic.canLeaveAddDogStep(hasExistingDogs: false, hasTypedDogName: false))
        XCTAssertTrue(OnboardingLogic.canLeaveAddDogStep(hasExistingDogs: false, hasTypedDogName: true))
    }
}
