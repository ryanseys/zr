module Probe
  # A question no compile-time fold can answer, the way bundler asks
  # `Gem::Platform.local.cpu`. Every guard below reads it.
  def self.cpu
    ["arm", "64"].join
  end
end

# Three bodies for one name, two of them guarded: the counts differ by two.
module Probe
  class ThreeBodies
    [:tag].each { |n| attr_accessor(n) }
    if Probe.cpu == "universal"
      def which = "first guard"
    end
    if Probe.cpu == "sparc"
      def which = "second guard"
    end
    def which = "real"
  end
end
p Probe::ThreeBodies.new.which

