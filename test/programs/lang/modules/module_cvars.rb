# Class variables (`@@var`) declared in a module body work the same
# as in a class body.

module Tep
  @@session_secret = ""

  def self.session_secret
    @@session_secret
  end

  def self.session_secret=(v)
    @@session_secret = v
  end
end

# Read default
puts Tep.session_secret.length    # 0

# Write + read back
Tep.session_secret = "hello"
puts Tep.session_secret           # hello

# Read again to confirm the global persists
puts Tep.session_secret           # hello

# A bare top-level `@@x` does not store into the same namespace. Only a
# `class`/`module` body opens the cref that `@@x` resolves against, so Ruby
# raises here. See `class_variable_cref_scope.rb` for the full rule.
begin
  @@plain = 42
rescue RuntimeError => e
  puts e.message                  # class variable access from toplevel
end
