import Testing

@testable import Owlet

@Test func adjacentSelectionRespectsFilteredOrderAndBoundaries() {
    #expect(adjacentSelection(in: [3, 1, 7], to: 1, offset: -1) == 3)
    #expect(adjacentSelection(in: [3, 1, 7], to: 1, offset: 1) == 7)
    #expect(adjacentSelection(in: [3, 1], to: 3, offset: -1) == nil)
    #expect(adjacentSelection(in: [3, 1], to: 1, offset: 1) == nil)
    #expect(adjacentSelection(in: [3, 1], to: 7, offset: 1) == nil)
    #expect(adjacentSelection(in: [3, 1], to: nil, offset: 1) == nil)
    #expect(adjacentSelection(in: [Int](), to: 1, offset: 1) == nil)
}
