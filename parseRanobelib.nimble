# Package

version       = "0.1.0"
author        = "levovix0"
description   = "ranobelib parser"
license       = "MIT"
srcDir        = "src"
bin           = @["parseRanobelib"]


# Dependencies

requires "nim >= 1.6.8"
requires "localize >= 0.3", "fusion", "argparse", "filetype"
