# frozen_string_literal: true

# The end of lib/zr/binary.rb in each build of zr's own code
# (`Hir::Build::Loader.tails`): the code that loads it runs in a zr
# binary. CRuby never reads this file.
Zr::Binary::BUILT = true
