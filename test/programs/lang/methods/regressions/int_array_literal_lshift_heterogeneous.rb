# `<Integer array literal> << <non-Integer>` shape (`[1, 2] << "c"`).
# Pushing a non-Integer element onto a literal Integer array gives
# a heterogeneous array, as in CRuby.
#
# This test covers direct ArrayNode literals on the LHS only, not a
# stored ivar / local (`@slots = [nil] * N; @slots << ...`).
p ([1, 2] << "c") == [1, 2, "c"]       # true
p ([1, 2] << nil) == [1, 2, nil]       # true
p ([1, 2] << 3) == [1, 2, 3]           # true (int <<, no lift)
