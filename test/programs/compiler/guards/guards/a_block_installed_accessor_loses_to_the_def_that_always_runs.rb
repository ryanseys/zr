module Probe
  # A question no compile-time fold can answer, the way bundler asks
  # `Gem::Platform.local.cpu`. Every guard below reads it.
  def self.cpu
    ["arm", "64"].join
  end
end

# The pass's own job, unchanged: a block-installed accessor loses to the
# `def` written below it, and so does a macro a class method expands.
module Probe
  class StillPositional
    [:y].each { |a| attr_writer(a) }
    def y=(v)
      @y = [v, v]
    end
    attr_reader :y
  end

  class MacroPack
    def self.make(n) = attr_writer(n)
    make :z
    def z=(v)
      @z = [v, v]
    end
    attr_reader :z
  end
end
s = Probe::StillPositional.new
s.y = 1
p s.y
m = Probe::MacroPack.new
m.z = 2
p m.z
