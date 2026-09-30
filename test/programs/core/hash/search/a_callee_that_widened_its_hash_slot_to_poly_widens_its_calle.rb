# A hash goes from `parse` to `assign`. `assign` stores both a String
# and a Hash as values in it. The caller passes the same hash object,
# so the caller must also accept values of mixed types.
#
# This is the shape of a form parser in a blog app: the parser calls
# a helper that stores `into[k] = val` (a String) and `into[k] = {}`
# (a Hash) in the same hash.

module Form
  # The body stores a String AND a Hash as values of `into`.
  def self.assign(into, k, v)
    if k.include?("[")
      into[k] = {}
    else
      into[k] = v
    end
  end

  # This passes `into` on to `assign`, so it holds mixed values too.
  def self.parse(input, into)
    input.split("&").each { |pair| assign(into, pair, "v") }
  end

  # The driver starts with a literal that holds a String value and
  # a Hash value, then passes it through the chain.
  def self.run
    h = { "x" => "v", "nested" => {} }
    parse("a=1&b=2", h)
    h.length
  end
end

puts Form.run
