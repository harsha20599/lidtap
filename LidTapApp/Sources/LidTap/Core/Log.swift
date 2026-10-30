import os

/// Unified logging. Query with: log show --predicate 'subsystem == "dev.lidtap"' --info
enum Log {
    static let app = Logger(subsystem: "dev.lidtap", category: "app")
    static let sensor = Logger(subsystem: "dev.lidtap", category: "sensor")
    static let action = Logger(subsystem: "dev.lidtap", category: "action")
}
