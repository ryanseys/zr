# A `shareable_constant_value` comment holds from its line to the end of
# its scope, and a block's scope is open to the one around it, as
# pm_parser_scope_shareable_constant_set marks them.
module Literal
  # shareable_constant_value: literal
  A = [[1], "a"]
  class Inner
    B = { k: ["v"] }
  end
  [1].each { D = ["d"] }
end
E = ["e"]

p Ractor.shareable?(Literal::A), Literal::A[0].frozen?
p Ractor.shareable?(Literal::Inner::B)
p Ractor.shareable?(Literal::D)
p Ractor.shareable?(E), E.frozen?

module Copied
  # shareable_constant_value: experimental_copy
  F = [+"f"]
  # shareable_constant_value: none
  G = [+"g"]
end
p Ractor.shareable?(Copied::F), Ractor.shareable?(Copied::G)
