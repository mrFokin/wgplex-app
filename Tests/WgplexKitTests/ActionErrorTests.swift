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
        XCTAssertEqual(actionErrorText(CancellationError()), "Ошибка")
    }
}
