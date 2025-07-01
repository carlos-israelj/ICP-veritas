let upstream = https://github.com/dfinity/vessel-package-set/releases/download/mo-0.11.1-20240411/package-set.dhall sha256:2c9af79fa9da72e28b5b88b3726dfa7e25ff4b21f4f3dafc2b914b67cf2e1a7d

let Package =
    { name : Text, version : Text, repo : Text, dependencies : List Text }

let additions = [] : List Package
let overrides = [] : List Package

in  upstream # additions # overrides