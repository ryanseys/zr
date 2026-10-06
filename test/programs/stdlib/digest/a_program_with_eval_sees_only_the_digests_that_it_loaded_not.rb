# A program with eval carries zr's compiler, which loads digest/sha2 for
# itself. The program's Digest has only what the program loaded.
eval("1")
require "digest"
p Digest.constants(false).sort, Digest.const_defined?(:SHA256, false)
p Digest::SHA256.hexdigest("zr")[0, 16]
p Digest.constants(false).sort
