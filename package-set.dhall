let upstream = https://github.com/dfinity/vessel-package-set/releases/download/mo-0.6.7-20210818/package-set.dhall sha256:c4bd3b9ffaf6b48d21841545306d9f69b57e79ce3b1ac5e1f63b068ca4f89957
let Package = { name : Text, version : Text, repo : Text, dependencies : List Text }

let additions = [
  { name = "ext"
  , repo = "https://github.com/aviate-labs/ext.std"
  , version = "v0.1.1"
  , dependencies = ["base", "principal"]
  },
  { name = "ext-toniq"
  , repo = "https://github.com/jorgenbuilder/extendable-token"
  , version = "main"
  , dependencies = ["base"]
  },
  { name = "principal"
  , repo = "https://github.com/aviate-labs/principal.mo"
  , version = "v0.2.1"
  , dependencies = ["base", "sha", "encoding"]
  },
  { name = "sha"
  , repo = "https://github.com/aviate-labs/sha.mo"
  , version = "v0.1.1"
  , dependencies = ["base", "encoding"]
  },
  { name = "encoding"
  , repo = "https://github.com/aviate-labs/encoding.mo"
  , version = "v0.2.1"
  , dependencies = ["base"]
  },
  { name = "assets"
  , repo = "https://github.com/aviate-labs/asset-storage.mo"
  , version = "main"
  , dependencies = ["base"]
  }
] : List Package

in  upstream # additions
