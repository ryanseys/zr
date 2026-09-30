module Probe
  # A question no compile-time fold can answer, the way bundler asks
  # `Gem::Platform.local.cpu`. Every guard below reads it.
  def self.cpu
    ["arm", "64"].join
  end
end

# The same pair in one file: guarded first, unguarded second.
module Probe
  class GuardedFirst
    [:tag].each { |n| attr_accessor(n) }
    if Probe.cpu == "universal"
      ONLY = "universal"
      def which = ONLY
      def self.which = ONLY
    end
  end

  class GuardedFirst
    def which = "real"
    def self.which = "real class method"
  end
end
p Probe::GuardedFirst.new.which
p Probe::GuardedFirst.which

