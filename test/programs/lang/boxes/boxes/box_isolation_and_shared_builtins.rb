# The keystone: a box-required file's classes are DISTINCT from main's
# (same file, different class objects), builtins are SHARED
# (`box::String == String`), a box top-level constant is readable
# externally, and box gvars are invisible in main -- all per the CRuby
# box model.



require_relative "box_isolation/main"
