# `module M; def self.X; ...; end; end` re-opened with a second
# `def self.X`, which can return a different type. In Ruby the
# last definition wins.

module M
  def self.greet
    "first"
  end
end

module M
  def self.greet
    "second"
  end
  def self.only_in_reopen
    "extra"
  end
end

# Last definition wins.
puts M.greet
# Method unique to the reopen is also available.
puts M.only_in_reopen
