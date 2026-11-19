// Checks an EdDSA (ed25519) signature of a file against a public key, the way
// Sparkle checks an update before installing it. The release workflow runs it
// with the SUPublicEDKey of the built app, so a release fails if the
// SPARKLE_ED_PRIVATE_KEY secret does not match the key installed copies trust.
//
// Usage: swift scripts/verify-ed-signature.swift <base64 public key> <base64 signature> <file>
// Exits 0 if the signature is valid, 1 if it is not, 2 on bad arguments.
import CryptoKit
import Foundation

func fail(_ message: String, _ code: Int32) -> Never {
    FileHandle.standardError.write(Data("verify-ed-signature: \(message)\n".utf8))
    exit(code)
}

let args = CommandLine.arguments
guard args.count == 4 else {
    fail("usage: verify-ed-signature.swift <base64 public key> <base64 signature> <file>", 2)
}
guard let keyData = Data(base64Encoded: args[1]),
      let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData) else {
    fail("the public key is not a base64 ed25519 key", 2)
}
guard let signature = Data(base64Encoded: args[2]), signature.count == 64 else {
    fail("the signature is not a base64 ed25519 signature", 2)
}
guard let file = FileManager.default.contents(atPath: args[3]) else {
    fail("cannot read \(args[3])", 2)
}
guard publicKey.isValidSignature(signature, for: file) else {
    fail("the signature of \(args[3]) does not match the public key", 1)
}
print("EdDSA signature of \(args[3]) is valid")
