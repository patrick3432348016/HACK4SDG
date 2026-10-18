import Foundation
import Testing
@testable import StreetWalk

// D-3 neighbor search ignores spaces, case and simplified/traditional differences.
struct NeighborSearchTests {
    @Test func 简体打都搵到繁体名同楼层() {
        let name = AppStore.searchKey("陳太")
        let place = AppStore.searchKey("皇順樓 8 樓")
        #expect(name.contains(AppStore.searchKey("陈")))
        #expect(place.contains(AppStore.searchKey("8楼")))
        #expect(place.contains(AppStore.searchKey("皇顺楼")))
        #expect(AppStore.searchKey("Wong Wui House").contains(AppStore.searchKey("wong wui")))
        #expect(!name.contains(AppStore.searchKey("李")))
    }
}
