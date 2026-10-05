# Both lines of the reassigned-constant warning go through Warning.warn,
# so a program that catches warnings gets the second line too.
module Warning
  def self.warn(message, category: nil)
    print "caught: ", message.sub(/\A.*?:\d+: /, "")
  end
end
C = Class.new
C.const_set("X\u{5b9a 6570}", 1)
C.const_set("X\u{5b9a 6570}", 2)
Y = 1
Y = 2
