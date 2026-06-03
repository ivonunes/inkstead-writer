import Foundation

struct PlumeResolvedAsset {
    var publicPath: String
    var kind: PlumeResolvedAssetKind
}

enum PlumeResolvedAssetKind {
    case external
    case publicPath
    case file(URL, publicPath: String?)
}
