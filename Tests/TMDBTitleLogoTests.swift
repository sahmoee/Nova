import XCTest
@testable import Nova

final class TMDBTitleLogoTests: XCTestCase {
    func testEnglishTitleArtworkWinsOverHigherRatedNeutralLogo() throws {
        let response = try decode("""
        {"logos":[
          {"file_path":"/neutral.png","iso_639_1":null,"width":900,"height":300,"vote_average":9},
          {"file_path":"/english.png","iso_639_1":"en","width":700,"height":250,"vote_average":5}
        ]}
        """)
        XCTAssertEqual(response.preferredLogoURL?.absoluteString,
                       "https://image.tmdb.org/t/p/original/english.png")
    }

    func testNeutralFallbackRejectsUnsupportedLanguageFormatAndDimensions() throws {
        let response = try decode("""
        {"logos":[
          {"file_path":"/french.png","iso_639_1":"fr","width":900,"height":300},
          {"file_path":"/vector.svg","iso_639_1":"en","width":900,"height":300},
          {"file_path":"/invalid.png","iso_639_1":"en","width":0,"height":300},
          {"file_path":"/neutral.png","iso_639_1":null,"width":600,"height":220}
        ]}
        """)
        XCTAssertEqual(response.preferredLogoURL?.lastPathComponent, "neutral.png")
    }

    func testRatingTiesUseVotesThenResolutionAndStablePath() throws {
        let response = try decode("""
        {"logos":[
          {"file_path":"/z.png","iso_639_1":"en","width":900,"height":300,"vote_average":5,"vote_count":3},
          {"file_path":"/a.png","iso_639_1":"en","width":900,"height":300,"vote_average":5,"vote_count":3},
          {"file_path":"/small.png","iso_639_1":"en","width":500,"height":200,"vote_average":5,"vote_count":3},
          {"file_path":"/few-votes.png","iso_639_1":"en","width":1000,"height":300,"vote_average":5,"vote_count":1}
        ]}
        """)
        XCTAssertEqual(response.preferredLogoURL?.lastPathComponent, "a.png")
    }

    func testNoSupportedArtworkKeepsTextFallback() throws {
        XCTAssertNil(try decode("{\"logos\":[]}").preferredLogoURL)
        XCTAssertNil(try decode("""
        {"logos":[{"file_path":"/title.jpg","iso_639_1":"en","width":800,"height":200}]}
        """).preferredLogoURL)
    }

    private func decode(_ json: String) throws -> TMDBTitleImages {
        try JSONDecoder().decode(TMDBTitleImages.self, from: Data(json.utf8))
    }
}
