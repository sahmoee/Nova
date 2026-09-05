// Native checks are concatenated after the exact NovaPresentationPolicy production
// declaration from StateViews.swift. No iOS simulator or duplicated policy is used.
func expect(_ condition: @autoclosure () -> Bool, _ name: String) {
    precondition(condition(), "FAILED: \(name)")
    print("PASS: \(name)")
}

expect(NovaPresentationPolicy.searchQuery(" English UK\n") == "English UK", "trim search boundaries")
expect(NovaPresentationPolicy.searchQuery("\n\t ").isEmpty, "whitespace-only search")
expect(NovaPresentationPolicy.searchQuery("日本語 français") == "日本語 français", "preserve language characters")
expect(NovaPresentationPolicy.progress(.nan) == 0, "NaN progress")
expect(NovaPresentationPolicy.progress(.infinity) == 0, "infinite progress")
expect(NovaPresentationPolicy.progress(-1) == 0, "negative progress")
expect(NovaPresentationPolicy.progress(2) == 1, "over-complete progress")
expect(NovaPresentationPolicy.progress(0.7) == 0.7, "valid progress")
expect(NovaPresentationPolicy.rateBytes(nil) == nil, "missing rate")
expect(NovaPresentationPolicy.rateBytes(.nan) == nil, "NaN rate")
expect(NovaPresentationPolicy.rateBytes(.infinity) == nil, "infinite rate")
expect(NovaPresentationPolicy.rateBytes(-1) == nil, "negative rate")
expect(NovaPresentationPolicy.rateBytes(0) == nil, "stopped rate")
expect(NovaPresentationPolicy.rateBytes(Double(Int64.max)) == nil, "overflow rate")
expect(NovaPresentationPolicy.rateBytes(2048.5) == 2048, "valid transfer rate")
struct Sample: Equatable { let id: String; let value: Int }
let first = Sample(id: "en", value: 1)
let second = Sample(id: "fr", value: 2)
expect(NovaPresentationPolicy.unique([first, second, Sample(id: "en", value: 3)], by: \.id) == [first, second], "stable first-result identity")
expect(NovaPresentationPolicy.unique([Sample](), by: \.id).isEmpty, "empty identity list")
print("17 Nova UI policy checks passed")
