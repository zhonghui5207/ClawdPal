import Testing
@testable import ClawdPalCore

struct PetMoodMapperTests {
    @Test
    func testReadingMapsToExplorer() {
        let event = AgentEvent(kind: .reading, toolName: "Read")
        let presentation = PetMoodMapper.presentation(for: event)

        #expect(presentation.mood == .explorer)
        #expect(presentation.bubbleText.contains("Read"))
    }

    @Test
    func testCommandMapsToStreet() {
        let event = AgentEvent(kind: .runningCommand, toolName: "Bash")
        let presentation = PetMoodMapper.presentation(for: event)

        #expect(presentation.mood == .street)
    }

    @Test
    func testEditingMapsToSuit() {
        let event = AgentEvent(kind: .editingCode, toolName: "Edit")
        let presentation = PetMoodMapper.presentation(for: event)

        #expect(presentation.mood == .suit)
    }

    @Test
    func testCompletionMapsToPajama() {
        let event = AgentEvent(kind: .completed)
        let presentation = PetMoodMapper.presentation(for: event)

        #expect(presentation.mood == .pajama)
        #expect(presentation.bubbleText == "Done.")
    }
}
