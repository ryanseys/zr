# Global variable compound writes — Or / And / Operator / Target.
# Each section uses its own global names, so no section changes the
# state of another.


# Mirror of LocalVariableOrWriteNode. Only assigns if the global
# is currently falsy (nil or false). An unassigned global is nil.
$or_count ||= 5    # never assigned, fires
puts $or_count     # 5
$or_count ||= 99   # already 5 (truthy in both), doesn't fire
puts $or_count     # 5
