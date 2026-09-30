# `Object.new.freeze` constants used as identity sentinels: each
# `Object.new` is a fresh object, `freeze` returns the receiver, and
# `==` compares identity.

NO_DIRECT_CALL = Object.new.freeze
HASH_MISS = Object.new.freeze

# Distinct sentinels: their addresses differ.
puts NO_DIRECT_CALL == HASH_MISS         # false
puts NO_DIRECT_CALL == NO_DIRECT_CALL    # true
puts HASH_MISS == HASH_MISS              # true
