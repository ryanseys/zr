# Inside a `module M` body, a bare method-name argument (`M.use(h)`,
# where `h` resolves to `M.h`) takes the return type of `M.h`, a
# Hash. So `opts.length` in the called method answers the Hash size.

module M
  def self.h
    {"" => ""}
  end
  def self.use(opts)
    opts.length
  end
  M.use(h)
end

puts M.use(M.h)
