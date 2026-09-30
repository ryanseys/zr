# Global variable compound writes — Or / And / Operator / Target.
# Each section uses its own global names, so no section changes the
# state of another.


# Mirror of LocalVariableOperatorWriteNode, but on a global.
$counter = 0
$counter += 1
$counter += 5
puts $counter   # 6
$counter -= 2
puts $counter   # 4
$counter *= 3
puts $counter   # 12
$counter /= 4
puts $counter   # 3
