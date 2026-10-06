# A scaffolded ext (json) is still require-gated: its constant is a
# NameError until `require "json"` fires, exactly like the fully-built
# ones -- scaffolding changes only what the METHODS do, not the gate.

puts JSON.generate([1])
