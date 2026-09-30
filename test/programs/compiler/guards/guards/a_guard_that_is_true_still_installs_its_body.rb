module Probe
  # A question no compile-time fold can answer, the way bundler asks
  # `Gem::Platform.local.cpu`. Every guard below reads it.
  def self.cpu
    ["arm", "64"].join
  end
end

# A guard that is TRUE still installs, or the fix would just be "never
# install a guarded body".
module Probe
  class GuardTaken
    [:tag].each { |n| attr_accessor(n) }
    def which = "real"
    def self.which = "real class method"
    if Probe.cpu == "arm64"
      def which = "taken"
      def self.which = "taken class method"
    end
  end
end
p Probe::GuardTaken.new.which
p Probe::GuardTaken.which

