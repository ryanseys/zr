# `autoload` declares the constant, so a const_added hook that raises
# raises out of the autoload, as it does out of an assignment.
module M
  def self.const_added(name) = raise("added #{name}")
  begin
    autoload :Foo, "foo"
  rescue => e
    p e.message
  end
  p autoload?(:Foo)
  p constants
end

__END__
"added Foo"
"foo"
[:Foo]
