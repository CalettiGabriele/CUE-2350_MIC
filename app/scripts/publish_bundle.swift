import Darwin
import Foundation

// Both paths must be on the same filesystem. Never move the existing bundle
// aside: if swapping is unsupported, fail with the destination untouched.
let args = CommandLine.arguments
guard args.count == 3 else {
    fputs("Usage: publish_bundle.swift <staged-app> <destination-app>\n", stderr)
    exit(2)
}
let source = args[1]
let destination = args[2]

while true {
    if renamex_np(source, destination, UInt32(RENAME_SWAP)) == 0 {
        break // The old bundle is now at source and will be removed by the caller.
    }
    let swapError = errno
    guard swapError == ENOENT else {
        fputs("Cannot atomically exchange bundles: \(String(cString: strerror(swapError)))\n", stderr)
        exit(1)
    }
    if renamex_np(source, destination, UInt32(RENAME_EXCL)) == 0 {
        break // Initial publication; do not replace a destination that appeared meanwhile.
    }
    let installError = errno
    if installError == EEXIST { continue }
    fputs("Cannot atomically publish bundle: \(String(cString: strerror(installError)))\n", stderr)
    exit(1)
}
