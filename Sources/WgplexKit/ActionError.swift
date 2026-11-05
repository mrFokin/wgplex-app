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
    case .configInvalid(let errors, _):
        return errors.isEmpty
            ? "Конфиг не применён. Работает прежний конфиг"
            : "Конфиг не применён: \(errors.count) \(errorsWord(errors.count)). Работает прежний конфиг"
    case .notConfigured:
        return "Конфиг не применён"
    case .some:
        return "Ошибка демона"
    case nil:
        return "Демон недоступен"
    }
}

/// Russian plural of "ошибка" for the count `n`.
private func errorsWord(_ n: Int) -> String {
    if n % 100 >= 11 && n % 100 <= 14 { return "ошибок" }
    switch n % 10 {
    case 1: return "ошибка"
    case 2, 3, 4: return "ошибки"
    default: return "ошибок"
    }
}
