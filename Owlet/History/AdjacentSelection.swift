func adjacentSelection<ID: Equatable>(in ids: [ID], to selection: ID?, offset: Int) -> ID? {
    guard let selection, let index = ids.firstIndex(of: selection) else { return nil }
    let next = index + offset
    return ids.indices.contains(next) ? ids[next] : nil
}
