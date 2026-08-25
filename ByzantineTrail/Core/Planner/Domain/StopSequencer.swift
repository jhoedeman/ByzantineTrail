import Foundation

/// Orders the stops of a single day.
///
/// This is an *open* TSP by default — a path, not a loop — because most days
/// start and end wherever the traveller happens to be. Pass `closed: true` when
/// the day returns to a lodging anchor.
///
/// Note what "optimal" means here: optimal with respect to the *estimated*
/// distances this is fed. Straight-line distance can mislead where water or
/// walls intervene, which is why M7b offers a re-optimize pass over resolved
/// routes. Never present the result to a user as "the optimal route".
enum StopSequencer {
    /// Above this many stops, exact Held-Karp becomes too slow and the
    /// nearest-neighbour + 2-opt heuristic below takes over. At n = 12 the exact solve is n^2 * 2^n ~ 590k
    /// operations — a few milliseconds.
    static let exactLimit = 12

    static func sequence(coordinates: [Coordinate],
                         mode: TravelMode,
                         estimator: any TravelEstimating,
                         pinnedPositions: Set<Int> = [],
                         closed: Bool = false) -> [Int] {
        let n = coordinates.count
        guard n > 2 else { return Array(0..<n) }

        let cost = matrix(coordinates, mode, estimator)

        if pinnedPositions.isEmpty && n <= exactLimit {
            return closed ? heldKarpClosedTour(cost) : heldKarpOpenPath(cost)
        }

        let valid = pinnedPositions.filter { $0 >= 0 && $0 < n }
        let seed = valid.isEmpty
            ? nearestNeighbour(cost)
            : pinnedSeed(cost, pinned: valid)
        return twoOpt(seed, cost, pinned: valid, closed: closed)
    }

    /// Total travel time for an order. Used by diagnostics and by tests.
    static func totalSeconds(order: [Int],
                             coordinates: [Coordinate],
                             mode: TravelMode,
                             estimator: any TravelEstimating,
                             closed: Bool = false) -> TimeInterval {
        guard order.count > 1 else { return 0 }
        var total: TimeInterval = 0
        for i in 0..<(order.count - 1) {
            total += estimator.seconds(from: coordinates[order[i]],
                                       to: coordinates[order[i + 1]], mode: mode)
        }
        if closed, let first = order.first, let last = order.last {
            total += estimator.seconds(from: coordinates[last],
                                       to: coordinates[first], mode: mode)
        }
        return total
    }

    // MARK: - Cost matrix

    static func matrix(_ coordinates: [Coordinate],
                       _ mode: TravelMode,
                       _ estimator: any TravelEstimating) -> [[Double]] {
        coordinates.map { a in
            coordinates.map { b in estimator.seconds(from: a, to: b, mode: mode) }
        }
    }

    // MARK: - Exact: minimum Hamiltonian path (open)

    private static func heldKarpOpenPath(_ cost: [[Double]]) -> [Int] {
        let n = cost.count
        let full = 1 << n
        var dp = [[Double]](repeating: [Double](repeating: .infinity, count: n),
                            count: full)
        var parent = [[Int]](repeating: [Int](repeating: -1, count: n), count: full)

        // A path may start anywhere.
        for j in 0..<n { dp[1 << j][j] = 0 }

        for mask in 1..<full {
            for j in 0..<n where mask & (1 << j) != 0 {
                let base = dp[mask][j]
                if base == .infinity { continue }
                for k in 0..<n where mask & (1 << k) == 0 {
                    let next = mask | (1 << k)
                    let candidate = base + cost[j][k]
                    if candidate < dp[next][k] {
                        dp[next][k] = candidate
                        parent[next][k] = j
                    }
                }
            }
        }

        var bestEnd = 0
        var best = Double.infinity
        for j in 0..<n where dp[full - 1][j] < best {
            best = dp[full - 1][j]
            bestEnd = j
        }
        return reconstruct(parent: parent, end: bestEnd, n: n)
    }

    // MARK: - Exact: minimum Hamiltonian cycle (closed, anchored at 0)

    private static func heldKarpClosedTour(_ cost: [[Double]]) -> [Int] {
        let n = cost.count
        let full = 1 << n
        var dp = [[Double]](repeating: [Double](repeating: .infinity, count: n),
                            count: full)
        var parent = [[Int]](repeating: [Int](repeating: -1, count: n), count: full)

        dp[1][0] = 0   // the tour is anchored at index 0

        for mask in 1..<full where mask & 1 != 0 {
            for j in 0..<n where mask & (1 << j) != 0 {
                let base = dp[mask][j]
                if base == .infinity { continue }
                for k in 1..<n where mask & (1 << k) == 0 {
                    let next = mask | (1 << k)
                    let candidate = base + cost[j][k]
                    if candidate < dp[next][k] {
                        dp[next][k] = candidate
                        parent[next][k] = j
                    }
                }
            }
        }

        var bestEnd = 1
        var best = Double.infinity
        for j in 1..<n {
            let closingCost = dp[full - 1][j] + cost[j][0]
            if closingCost < best {
                best = closingCost
                bestEnd = j
            }
        }
        return reconstruct(parent: parent, end: bestEnd, n: n)
    }

    private static func reconstruct(parent: [[Int]], end: Int, n: Int) -> [Int] {
        var path: [Int] = []
        var mask = (1 << n) - 1
        var node = end
        while node != -1 {
            path.append(node)
            let previous = parent[mask][node]
            mask &= ~(1 << node)
            node = previous
        }
        return path.reversed()
    }

    // MARK: - Heuristic: nearest neighbour + 2-opt

    private static func nearestNeighbour(_ cost: [[Double]]) -> [Int] {
        let n = cost.count
        var visited = [Bool](repeating: false, count: n)
        var order = [0]
        visited[0] = true
        var current = 0

        for _ in 1..<n {
            var best = -1
            var bestCost = Double.infinity
            for k in 0..<n where !visited[k] && cost[current][k] < bestCost {
                bestCost = cost[current][k]
                best = k
            }
            guard best >= 0 else { break }
            visited[best] = true
            order.append(best)
            current = best
        }
        return order
    }

    /// Seeds an order in which every pinned position already holds its own
    /// stop; free positions are filled greedily from the preceding stop.
    private static func pinnedSeed(_ cost: [[Double]], pinned: Set<Int>) -> [Int] {
        let n = cost.count
        var order = [Int](repeating: -1, count: n)
        for p in pinned { order[p] = p }

        var remaining = Set(0..<n).subtracting(pinned)
        var current: Int?

        for position in 0..<n {
            if order[position] != -1 {
                current = order[position]
                continue
            }
            guard !remaining.isEmpty else { break }
            let pick: Int
            if let from = current {
                pick = remaining.min { cost[from][$0] < cost[from][$1] } ?? remaining.first!
            } else {
                pick = remaining.min() ?? remaining.first!
            }
            order[position] = pick
            remaining.remove(pick)
            current = pick
        }
        return order
    }

    /// 2-opt: repeatedly reverse a segment when doing so shortens the route.
    /// A segment containing a pinned position is skipped, because reversing it
    /// would move that stop away from the position the user chose.
    ///
    /// An OPEN path may reverse a prefix (`i == 0`) — the path is free to start
    /// anywhere, and forbidding it strands nearest-neighbour seeds that begin in
    /// the middle of a line. A CLOSED tour keeps `i >= 1` so it stays anchored
    /// at index 0.
    private static func twoOpt(_ initial: [Int],
                               _ cost: [[Double]],
                               pinned: Set<Int>,
                               closed: Bool) -> [Int] {
        var order = initial
        let n = order.count
        guard n > 3 else { return order }

        let lowerBound = closed ? 1 : 0
        var improved = true
        while improved {
            improved = false
            for i in lowerBound..<(n - 1) {
                for j in (i + 1)..<n {
                    if pinned.contains(where: { $0 >= i && $0 <= j }) { continue }
                    if swapDelta(order, cost, i, j, closed) < -1e-9 {
                        order[i...j].reverse()
                        improved = true
                    }
                }
            }
        }
        return order
    }

    /// Change in total cost from reversing `order[i...j]`. Negative is better.
    private static func swapDelta(_ order: [Int],
                                  _ cost: [[Double]],
                                  _ i: Int,
                                  _ j: Int,
                                  _ closed: Bool) -> Double {
        let n = order.count
        let head = order[i]
        let tail = order[j]

        // Edge on the far side of the segment, which the reversal replaces.
        let removedEdge: Double
        let addedEdge: Double
        if j + 1 < n {
            removedEdge = cost[tail][order[j + 1]]
            addedEdge = cost[head][order[j + 1]]
        } else if closed {
            removedEdge = cost[tail][order[0]]
            addedEdge = cost[head][order[0]]
        } else {
            removedEdge = 0
            addedEdge = 0
        }

        // Reversing a prefix of an open path has no preceding edge at all.
        guard i > 0 else { return addedEdge - removedEdge }

        let before = order[i - 1]
        return (cost[before][tail] + addedEdge) - (cost[before][head] + removedEdge)
    }
}
