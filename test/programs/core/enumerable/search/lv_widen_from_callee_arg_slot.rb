# A callee's body writes values of mixed types into a Hash param. The
# caller's local Hash must accept those values too.
#
# Shape (real-blog parse_request / parse_form_into):
#
#   def assign(into, k, v)
#     # heterogeneous body -- `into` gets values of mixed types
#     if k.include?("[")
#       into[k] = {}
#     else
#       into[k] = v
#     end
#   end
#
#   def parse(input, into)
#     input.split("&").each { |p| assign(into, p, "v") }
#   end
#
#   def run
#     params = {}
#     parse("a=1&b=2", params)        # the callee stores mixed values
#     params
#   end

module Form
  def self.assign(into, k, v)
    if k.include?("[")
      into[k] = {}
    else
      into[k] = v
    end
  end

  def self.parse(input, into)
    input.split("&").each { |p| assign(into, p, "v") }
  end

  def self.run
    params = {}
    parse("a=1&b=2", params)
    params["a"]
  end
end

puts Form.run
