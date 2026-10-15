# Kernel#exit reads its status as NUM2INT does: true and false, else an
# Integer that fits a C int, so a wider one raises RangeError before any
# SystemExit. SystemExit.new takes what to_int makes of its first
# argument, a Float too; anything else is its message.
[2**64, 2**63, -(2**63), 2**31, -(2**31) - 1, 2**31 - 1, 2.5, nil, "1", true, false, 3].each do |status|
  exit(status)
rescue SystemExit => e
  p [status, e.status, e.success?]
rescue RangeError, TypeError => e
  p [status, e.class, e.message]
end
[[2**64], [2.5], ["gone"], [4, "msg"], [false, "no"], [], [nil]].each do |args|
  e = SystemExit.new(*args)
  p [args, e.status, e.message]
end
