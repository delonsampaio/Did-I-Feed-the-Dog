import Foundation

func parseDeepLink(_ url: URL) -> UUID? {
    guard url.scheme == "didfeedthedog",
          url.host(percentEncoded: false) == "log",
          let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
          let petIdString = components.queryItems?.first(where: { $0.name == "petId" })?.value
    else { return nil }
    return UUID(uuidString: petIdString)
}
