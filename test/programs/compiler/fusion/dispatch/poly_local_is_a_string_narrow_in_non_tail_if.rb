# A local of no single type, narrowed by
# `if content.is_a?(String) ... end`, when the if is NOT in tail
# position. Inside the body, `Regexp.escape(content)` gets a String.

class Resp
  attr_reader :body
  def initialize(b); @body = b; end
end

class Tester
  attr_accessor :response

  def assert_select(selector, content_or_opts = nil, &block)
    body = response.body
    if content_or_opts.is_a?(Hash)
      content = nil
    else
      content = content_or_opts
    end
    if content.is_a?(String)
      pattern = Regexp.new("<#{selector}>#{Regexp.escape(content)}<")
      raise "no match" unless pattern.match?(body)
    end
    yield if block
  end
end

t = Tester.new
t.response = Resp.new("<h1>Title<")
t.assert_select("h1", "Title")
t.assert_select("div", { count: 1 })
puts "OK"
