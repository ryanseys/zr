module Probe
  # A question no compile-time fold can answer, the way bundler asks
  # `Gem::Platform.local.cpu`. Every guard below reads it.
  def self.cpu
    ["arm", "64"].join
  end
end

# ...and the other order.
module Probe
  class GuardedLast
    [:tag].each { |n| attr_accessor(n) }
    def which = "real"
  end

  class GuardedLast
    if Probe.cpu == "universal"
      def which = "universal"
    end
  end
end
p Probe::GuardedLast.new.which

