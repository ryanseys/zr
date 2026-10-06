module Probe
  # A question no compile-time fold can answer, the way bundler asks
  # `Gem::Platform.local.cpu`. Every guard below reads it.
  def self.cpu
    ["arm", "64"].join
  end
end

# Two units, the GUARDED reopen walked first -- the ordering that let a
# guarded body take the unguarded one's document position.
require_relative "guarded_def/base"
unit = Probe::Unit.new
p unit.extensions_dir
p Probe::Unit.channel
p Probe::Unit.const_defined?(:ONLY_IF_UNIVERSAL)
unit.tag = "tagged"
p unit.tag

