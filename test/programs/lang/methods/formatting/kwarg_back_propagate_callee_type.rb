# Kwarg passthrough: method outer forwards `inner(name: lvar)`,
# and inner's `name:` has a type from its default value or its
# body. The matching kwarg of outer gets that type too.
#
# This is the kwarg form of the positional case: the match is
# by kwarg name, not by position. The type can be any concrete
# type (a String, an Array of Integers, a Hash, and so on).

module Broadcasts
  def self.append(stream:, target:, html:)
    record(action: :append, stream: stream, target: target, html: html)
  end

  def self.record(action:, stream:, target:, html:)
    out = action.to_s + "|" + stream + "|" + target + "|len=" + html.length.to_s
    out
  end
end

puts Broadcasts.append(stream: "s", target: "t", html: "<div>")
