import Testing
@testable import Telocare

struct TelocareSkinResolverTests {
    @Test func equalsLaunchArgumentHasHighestPrecedence() {
        let resolved = TelocareSkinResolver.resolve(
            arguments: ["Telocare", "--skin=garden"],
            environment: ["TELOCARE_SKIN": "warm-coral"],
            infoDictionarySkin: "warm-coral",
            storedSkinID: .warmCoral
        )

        #expect(resolved == .garden)
    }

    @Test func splitLaunchArgumentHasPriorityOverEnvironment() {
        let resolved = TelocareSkinResolver.resolve(
            arguments: ["Telocare", "--skin", "garden"],
            environment: ["TELOCARE_SKIN": "warm-coral"],
            infoDictionarySkin: nil,
            storedSkinID: .warmCoral
        )

        #expect(resolved == .garden)
    }

    @Test func environmentHasPriorityOverInfoDictionaryAndStoredValue() {
        let resolved = TelocareSkinResolver.resolve(
            arguments: ["Telocare"],
            environment: ["TELOCARE_SKIN": "garden"],
            infoDictionarySkin: "warm-coral",
            storedSkinID: .warmCoral
        )

        #expect(resolved == .garden)
    }

    @Test func infoDictionaryHasPriorityOverStoredValue() {
        let resolved = TelocareSkinResolver.resolve(
            arguments: ["Telocare"],
            environment: [:],
            infoDictionarySkin: "garden",
            storedSkinID: .warmCoral
        )

        #expect(resolved == .garden)
    }

    @Test func storedValueUsedWhenNoOverridesExist() {
        let resolved = TelocareSkinResolver.resolve(
            arguments: ["Telocare"],
            environment: [:],
            infoDictionarySkin: nil,
            storedSkinID: .garden
        )

        #expect(resolved == .garden)
    }

    @Test func fallsBackToWarmCoralForUnknownValues() {
        let resolved = TelocareSkinResolver.resolve(
            arguments: ["Telocare", "--skin=unknown-theme"],
            environment: [:],
            infoDictionarySkin: nil,
            storedSkinID: nil
        )

        #expect(resolved == .warmCoral)
    }

    @Test func parsesAliases() {
        #expect(TelocareSkinResolver.parse("cheerful relaxing garden") == .garden)
        #expect(TelocareSkinResolver.parse("legacy") == .warmCoral)
    }
}
