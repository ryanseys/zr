# ruby loads rubygems and bundled_gems before the program's first line,
# so bundled_gems' LoadError#message is there from the start: it reads
# the path with String#tr, which raises for a byte that is no character,
# and the uncaught error then shows only its class. zr loads them at the
# first use of Gem, so until then the message is LoadError's own.
begin
  require "\xff"
rescue LoadError => e
  p((e.message rescue $!))
end
p $LOADED_FEATURES.grep(/bundled_gems\.rb\z/).size
