import Flutter
import UIKit
import XCTest
@testable import Runner

class RunnerTests: XCTestCase {

  func testColdStartLinkForwarderForwardsExactlyOnce() {
    let expectedURL = URL(string: "https://strnadi.cz/nahravka/42")!
    var forwardedURLs: [URL] = []

    let handled = ColdStartLinkForwarder.forward(expectedURL) { url in
      forwardedURLs.append(url)
    }

    XCTAssertTrue(handled)
    XCTAssertEqual(forwardedURLs, [expectedURL])
  }

  func testColdStartLinkForwarderIgnoresMissingURL() {
    var callbackCount = 0

    let handled = ColdStartLinkForwarder.forward(nil) { _ in
      callbackCount += 1
    }

    XCTAssertFalse(handled)
    XCTAssertEqual(callbackCount, 0)
  }

}
