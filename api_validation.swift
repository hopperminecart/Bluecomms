import Network
import Foundation

let params = NWParameters.tcp
params.includePeerToPeer = true

let browser = NWBrowser(for: .bonjour(type: "_bluecomms._tcp", domain: "local."), using: params)
let listener = try! NWListener(using: params)

print("Network API validation passed")
