/// Reassembles notification fragments for one message at a time.
public struct TandemPacketAssembler: Sendable {
    private var transactionID: UInt8?
    private var payload: [UInt8] = []

    public init() {}

    public mutating func feed(_ notification: [UInt8]) -> [UInt8]? {
        guard notification.count >= 2 else { return nil }
        let incomingID = notification[1]
        if transactionID != incomingID {
            transactionID = incomingID
            payload.removeAll(keepingCapacity: true)
        }
        payload.append(contentsOf: notification.dropFirst(2))
        guard notification[0] & 0x0F == 0 else { return nil }
        let message = payload
        payload.removeAll(keepingCapacity: true)
        transactionID = nil
        return message
    }
}
