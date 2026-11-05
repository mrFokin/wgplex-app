import Foundation

/// Short menu message for a failed tunnel/pause action (design 4).
public func actionErrorText(_ error: any Error) -> String {
    guard let e = error as? RPCError else { return "Ошибка" }
    switch e.kind {
    case .permissionDenied:
        return "Нет прав на управление"
    case .tunnelStartFailed:
        return "Туннель не поднялся"
    case .unknownTunnel:
        return "Туннель не найден"
    case .notConfigured:
        return "Конфиг не применён"
    case .some:
        return "Ошибка демона"
    case nil:
        return "Демон недоступен"
    }
}
