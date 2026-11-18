// Spike #28: makes a throwaway EdDSA (ed25519) key pair without touching the keychain.
// Writes <dir>/private.seed (base64 of the 32-byte seed, the format `generate_keys -x`
// exports and `sign_update --ed-key-file` reads) and <dir>/public.key (base64, the
// value for SUPublicEDKey).
import CryptoKit
import Foundation

let dir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let key = Curve25519.Signing.PrivateKey()
try key.rawRepresentation.base64EncodedString().write(toFile: dir + "/private.seed", atomically: true, encoding: .utf8)
try key.publicKey.rawRepresentation.base64EncodedString().write(toFile: dir + "/public.key", atomically: true, encoding: .utf8)
