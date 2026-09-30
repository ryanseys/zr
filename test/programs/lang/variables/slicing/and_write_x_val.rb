# Global variable compound writes — Or / And / Operator / Target.
# Each section uses its own global names, so no section changes the
# state of another.


# Mirror of LocalVariableAndWriteNode. Only assigns if the global
# is currently truthy.
$and_count = 5
$and_count &&= 10  # 5 is truthy, fires
puts $and_count    # 10
$and_count &&= 0   # 10 is truthy, fires
puts $and_count    # 0
