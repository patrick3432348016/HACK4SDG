import Foundation

/// Peer consent never substitutes for a local user action or a local UWB measurement.
struct ExchangeState {
    private(set) var localNear = false
    private(set) var peerNear = false
    private(set) var localConsent = false
    private(set) var peerConsent = false
    private(set) var receivedCard = false
    private(set) var peerStoredCard = false
    private(set) var cancelled = false

    var canConfirm: Bool { localNear && peerNear && !cancelled }
    var canExchange: Bool { canConfirm && localConsent && peerConsent }
    var complete: Bool { canExchange && receivedCard && peerStoredCard }
    mutating func markLocalNear() { if !cancelled { localNear = true } }
    mutating func markPeerNear() { if !cancelled { peerNear = true } }
    mutating func consentLocally() -> Bool {
        guard canConfirm, !localConsent else { return false }
        localConsent = true
        return true
    }
    mutating func consentFromPeer() { if !cancelled { peerConsent = true } }
    mutating func markCardStored() -> Bool {
        guard canExchange else { return false }
        receivedCard = true
        return true
    }
    mutating func markPeerReceipt() -> Bool {
        guard canExchange else { return false }
        peerStoredCard = true
        return true
    }
    mutating func cancel() { cancelled = true }
}

