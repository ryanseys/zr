# A program that evals carries the compiler, whose road loads ffi for
# its own use, out of sight. The program's own require of ffi brings it
# into sight: the files it loaded in turn and the constants they define
# are the program's, as ruby's one require loads them all.
eval "1"
p require("ffi")
p defined?(FFI), defined?(FFI::Pointer), FFI::Pointer.new(0).null?
p $LOADED_FEATURES.count { |f| f.include?("/ffi/") } > 20
p require("ffi")

__END__
true
"constant"
"constant"
true
true
false
