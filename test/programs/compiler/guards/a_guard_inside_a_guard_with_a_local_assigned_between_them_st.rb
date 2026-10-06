module Probe
  # A question no compile-time fold can answer, the way bundler asks
  # `Gem::Platform.local.cpu`. Every guard below reads it.
  def self.cpu
    ["arm", "64"].join
  end
end

# Bundler's actual nesting: a guard inside a guard, with a local assigned
# between them.
module Probe
  class Nested
    [:tag].each { |n| attr_accessor(n) }
    if Probe.cpu
      cpu = Probe.cpu
      if cpu == "universal"
        DEEP = "deep"
        def which = DEEP
      end
    end
    def which = "real"
  end
end
p Probe::Nested.new.which

