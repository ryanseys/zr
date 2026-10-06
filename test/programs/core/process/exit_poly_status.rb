# An `exit(status)` whose status expression is poly-typed (here a poly-hash
# get) uses the Integer in the value as the exit status.
h = { "status" => 0, "note" => "text" }
puts "before exit"
exit(h["status"])
