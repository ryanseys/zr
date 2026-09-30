# Global variable compound writes — Or / And / Operator / Target.
# Each section uses its own global names, so no section changes the
# state of another.


# `$a, $b = 1, 2` -- each LHS slot is a GlobalVariableTargetNode.
# It writes the same global that a plain `$a = ...` writes.
$ga, $gb = 1, 2
puts $ga          # 1
puts $gb          # 2
$ga, $gb = $gb, $ga    # swap
puts $ga          # 2
puts $gb          # 1
