# `require "prism"` out of the gem store reaches `prism/ffi.rb` even though
# zr builds and loads the gem's C extension: the DEBUG log shows
# `load C extension .../ext/prism/prism.bundle`, and `Prism.parse` still
# raises `uninitialized constant Prism::LibRubyParser::PrismString`.
#
# `prism` is the one gem in the C-API sweep with two backends, and its
# loader picks between them with `RUBY_ENGINE == "ruby"`, which zr answers
# `"ruby"`.


require "prism"

r = Prism.parse("1 + 2\n")
puts r.success?, r.value.class
puts Prism::VERSION
