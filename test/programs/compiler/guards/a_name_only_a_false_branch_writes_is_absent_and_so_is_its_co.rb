module Probe
  # A question no compile-time fold can answer, the way bundler asks
  # `Gem::Platform.local.cpu`. Every guard below reads it.
  def self.cpu
    ["arm", "64"].join
  end
end

# A name only a false branch writes is absent, and so is its constant.
module Probe
  class OnlyGuarded
    [:tag].each { |n| attr_accessor(n) }
    if Probe.cpu == "universal"
      NEVER = 1
      def missing = NEVER
    end
  end
end
p Probe::OnlyGuarded.instance_methods(false).include?(:missing)
p Probe::OnlyGuarded.const_defined?(:NEVER)
begin
  Probe::OnlyGuarded.new.missing
rescue NoMethodError => e
  p e.class.to_s
end

