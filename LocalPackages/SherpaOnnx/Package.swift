// swift-tools-version: 5.9
import PackageDescription

let sherpaRoot = Context.packageDirectory + "/../../ThirdParty/sherpa-onnx"
let sherpaLib = sherpaRoot + "/lib"

let package = Package(
    name: "SherpaOnnx",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CSherpaOnnx", targets: ["CSherpaOnnx"])
    ],
    targets: [
        .target(
            name: "CSherpaOnnx",
            path: "Sources/CSherpaOnnx",
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("include")
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-L\(sherpaLib)",
                    "-lsherpa-onnx-c-api",
                    "-lsherpa-onnx-core",
                    "-lonnxruntime",
                    "-lkaldi-decoder-core",
                    "-lkaldi-native-fbank-core",
                    "-lsherpa-onnx-kaldifst-core",
                    "-lsherpa-onnx-fstfar",
                    "-lsherpa-onnx-fst",
                    "-lssentencepiece_core",
                    "-lespeak-ng",
                    "-lpiper_phonemize",
                    "-lucd",
                    "-lkissfft-float",
                    "-lc++"
                ])
            ]
        )
    ]
)
