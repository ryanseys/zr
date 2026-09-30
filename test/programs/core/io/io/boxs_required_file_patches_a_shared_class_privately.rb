# A box loading a FILE (rather than an eval'd string) isolates the same
# way. The two routes reach the compiler differently -- a literal
# `box.eval` is spliced at compile time and a `require_relative` brings in
# a whole unit -- so both need saying.



require_relative "box_required_file/main"
