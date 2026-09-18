module Shout
  refine String do
    def shout = upcase + "!"
  end
end

module Quiet
  refine String do
    def quiet = downcase
  end
end

using Shout
p "a".shout

if ARGV.empty?
  using Quiet
  p "B".quiet
end

class K
  using Shout
  def call(s) = s.shout
end
p K.new.call("b")
