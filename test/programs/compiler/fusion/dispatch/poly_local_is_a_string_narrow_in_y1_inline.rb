# The is_a? narrow must also apply when the method gets a block.
# `check` gets a String, an Integer, and a call with only a block.

class Base
  def check(content = nil, &block)
    if content.is_a?(String)
      pattern = Regexp.new(Regexp.escape(content))
      raise "no match" unless pattern.match?(content)
    end
    yield if block
  end
end

class Sub < Base
  def run
    check("hello")
    check(123)        # makes content's static type poly
    check { nil }     # block-passing call triggers y1 inlining
  end
end

Sub.new.run
puts "OK"
