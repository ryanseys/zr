# frozen_string_literal: true

# A `class << obj` body opens the object's SINGLETON class, which no row
# can name -- a singleton is minted per object at run time. Each `def`
# becomes a `define_singleton_method`, and every other statement is
# lowered with `self` bound to `obj.singleton_class`, which is what
# `self` is inside that body.

class Config
  class << self
    def direct = :direct

    alias aliased direct

    attr_accessor :level

    # `self` is the singleton class, so a receiverless macro and an
    # explicit `self.` call both name it.
    self.send(:define_method, :made) { :made }

    private

    def hidden = :hidden
  end
end

p Config.direct, Config.aliased, Config.made
Config.level = 3
p Config.level
p Config.singleton_class.private_instance_methods(false).sort
p(begin
  Config.hidden
rescue NoMethodError
  :private
end)

# A block written in the body closes over that `self` too.
class Made
  class << self
    %w[a b].each { |n| define_method("m_#{n}") { n } }
  end
end

p Made.m_a, Made.m_b

# An arbitrary statement runs where it stands.
$log = []

class Logged
  class << self
    $log << :before
    def one = 1
    $log << :after
  end
end

p $log, Logged.one

# `undef` retires the name on the singleton class.
class Retired
  class << self
    def gone = :gone
    undef gone
  end
end

p Retired.respond_to?(:gone)

# `class << obj` on a plain object opens that one object's singleton.
o = Object.new

class << o
  def only = :only
end

p o.only, o.singleton_methods
p Object.new.respond_to?(:only)
