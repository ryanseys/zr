# frozen_string_literal: true

# A `def` under a guard is REGISTERED BUT NOT PROMISED: it claims no static
# row and installs where it stands, so the body has to run for the method to
# exist. A class body written under a guard is that same guard around every
# `def` it holds, which is what keeps a reopen the branch never took from
# adding its methods anyway.

def enabled? = [false].sample
def disabled? = [true].sample

class Widget
  def base = "base"
end

class Widget
  def extra = "extra"
end if enabled?

class Widget
  def other = "other"
end if disabled?

p Widget.instance_methods(false).sort
p Widget.new.other
begin
  Widget.new.extra
rescue NoMethodError => e
  puts "NoMethodError: #{e.name}"
end
p Widget.new.respond_to?(:extra)

# Both arms of one guard reopen the same class: only the arm that runs adds
# anything, and the constant is the same class either way.
class Impl
  def greet = "base"
end
if enabled?
  class Impl
    def greet = "yes"
    def only_yes = 1
  end
else
  class Impl
    def greet = "no"
    def only_no = 2
  end
end
p Impl.new.greet
p Impl.instance_methods(false).sort
p Impl.new.only_no

# A module reopened under a guard answers the same way.
module Flags
  def self.base = :base
end

module Flags
  def self.extra = :extra
end if disabled?

p Flags.extra
p Flags.singleton_methods(false).sort

# A guarded body still gives the class row its ivars and its class variables.
class Holder
  def initialize = @seen = []
  def seen = @seen
end

class Holder
  @@count = 0
  def push(x)
    @seen << x
    @@count += 1
    @@count
  end
end if disabled?

h = Holder.new
p h.push(:a)
p h.seen
