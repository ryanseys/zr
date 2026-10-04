# A return in an eval leaves the innermost lambda around it, through a
# Proc, as ruby finds it at run time. zr walks the scopes the compiler
# knows and raises LocalJumpError.

p(-> { eval("return :eval") }.call)
