# Marshal reads a Symbol's own text, so a Symbol#to_s that the program
# redefines changes neither a dump nor a load.
module Mixin; end
Point = Struct.new(:x, :y)
class Box
  def initialize(v) = (@v = v)
  attr_reader :v
end

class Symbol
  def to_s = nil
end

data = [:sym, :"üñí", Box.new(:inner), Point.new(1, :two), "s".extend(Mixin), { k: :v }]
bytes = Marshal.dump(data)
p bytes.bytesize
back = Marshal.load(bytes)
p back[0], back[1], back[2].v, back[3], back[4].singleton_class.include?(Mixin), back[5]
p Marshal.load(Marshal.dump(:again))
p "#{:foo}".nil?
