import Testing

@testable import YogSothothsEcho

// 標籤外圈的條碼（#5-1 使用者指定）：11 位數字 → UPC-A（第 12 位為檢查碼）→ 95 個模組（1＝黑條）

struct UPCABarcodeTests {
    /// 公認範例：03600029145 → 檢查碼 2
    @Test func checkDigit() {
        #expect(UPCABarcode.checkDigit("03600029145") == 2)
        #expect(UPCABarcode.checkDigit("07047045816") == 8)   // Python 獨立計算
    }

    @Test func modulesForKnownCode() throws {
        let modules = try #require(UPCABarcode.modules("03600029145"))
        #expect(modules.count == 95)
        let text = modules.map { $0 ? "1" : "0" }.joined()
        // 起始 101、左 6 碼（L 碼）、中間 01010、右 6 碼（R 碼）、結尾 101
        #expect(text == "101" + "0001101" + "0111101" + "0101111" + "0001101" + "0001101" + "0001101"
                + "01010" + "1101100" + "1110100" + "1100110" + "1011100" + "1001110" + "1101100" + "101")
    }

    @Test func rejectsWrongLengthOrNonDigits() {
        #expect(UPCABarcode.modules("1234") == nil)
        #expect(UPCABarcode.modules("0704704581a") == nil)
        #expect(UPCABarcode.modules("070470458161") == nil)   // 12 位不收（檢查碼由程式算）
    }
}
