# frozen_string_literal: true

# A name only the run time builds. Each of these verbs mints its methods
# where it stands rather than from a row, so the compile has nothing to
# emit and the call goes out as an ordinary send.

class Fields
  %i[a b].each { |n| attr_accessor n }

  def initialize
    @a = 1
    @b = 2
  end

  def orig = :orig

  COPY = :copy
  alias_method COPY, :orig
end

f = Fields.new
p f.a, f.b
f.a = 9
p f.a, f.copy
p Fields.instance_methods(false).sort

# An interpolated `alias` and `undef` name is a value the runtime takes
# exactly as it takes a literal.
class Named
  def base = :base

  n = 1
  alias :"base#{n}" :base
end

p Named.new.base1

class Retired
  def gone = :gone
  n = 2
  def gone2 = :gone2
  undef :"gone#{n}"
end

p Retired.new.gone
p Retired.new.respond_to?(:gone2)

# `` `cmd` `` runs the string through the shell, interpolated or not.
p `echo one`.strip
who = "two"
p `echo #{who}`.strip
p $?.success?
__END__
1
2
9
:orig
[:a, :a=, :b, :b=, :copy, :orig]
:base
:gone
false
"one"
"two"
true
