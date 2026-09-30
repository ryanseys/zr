# AliasGlobalVariableNode -- `alias $copy $orig`.
#
# $copy is a second name for the storage of $orig, so reads and
# writes of either share state. Out of scope: an alias inside a
# method body.

$orig = "hello"
alias $copy $orig
puts $copy        # hello

$orig = "updated"
puts $copy        # updated

$copy = "back"
puts $orig        # back
