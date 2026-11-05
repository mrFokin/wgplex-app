import XCTest

@testable import WgplexKit

final class ActionErrorTests: XCTestCase {
    func testTexts() {
        XCTAssertEqual(actionErrorText(RPCError.unavailable("x")), "Демон недоступен")
        XCTAssertEqual(
            actionErrorText(RPCError.server(code: 5, message: "m", data: nil)), "Нет прав на управление")
        XCTAssertEqual(
            actionErrorText(RPCError.server(code: 4, message: "m", data: nil)), "Туннель не поднялся")
        XCTAssertEqual(
            actionErrorText(RPCError.server(code: -32603, message: "m", data: nil)), "Ошибка демона")
        XCTAssertEqual(
            actionErrorText(RPCError.server(code: 2, message: "m", data: nil)), "Конфиг не применён")
        XCTAssertEqual(
            actionErrorText(RPCError.server(code: 3, message: "m", data: nil)), "Туннель не найден")
        XCTAssertEqual(actionErrorText(RPCError.transport("x")), "Демон недоступен")
        XCTAssertEqual(actionErrorText(CancellationError()), "Ошибка")
    }

    func testConfigInvalid() {
        func text(_ errors: [String]) -> String {
            let data = try! JSONEncoder().encode(["errors": errors])
            return actionErrorText(RPCError.server(code: 1, message: "m", data: data))
        }
        XCTAssertEqual(text(["a"]), "Конфиг не применён: 1 ошибка. Работает прежний конфиг")
        XCTAssertEqual(text(["a", "b"]), "Конфиг не применён: 2 ошибки. Работает прежний конфиг")
        XCTAssertEqual(
            text(Array(repeating: "x", count: 5)), "Конфиг не применён: 5 ошибок. Работает прежний конфиг")
        XCTAssertEqual(
            actionErrorText(RPCError.server(code: 1, message: "m", data: nil)),
            "Конфиг не применён. Работает прежний конфиг")
    }
}
