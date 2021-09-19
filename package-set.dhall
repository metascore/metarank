let upstream = https://github.com/dfinity/vessel-package-set/releases/download/mo-0.6.7-20210818/package-set.dhall sha256:c4bd3b9ffaf6b48d21841545306d9f69b57e79ce3b1ac5e1f63b068ca4f89957
let Package = { name : Text, version : Text, repo : Text, dependencies : List Text }

let additions = [{
    name = "assets",
    repo = "https://github.com/aviate-labs/asset-storage.mo",
    version = "asset-storage-0.7.0",
    dependencies = ["base"]
}, {
    name = "ext",
    repo = "https://github.com/jorgenbuilder/extendable-token",
    version = "main",
    dependencies = ["ext"]
}, {
    name = "dl-nft",
    repo = "https://github.com/DepartureLabsIC/non-fungible-token",
    version = "main",
    dependencies = ["dl-nft"]
}] : List Package

in  upstream # additions