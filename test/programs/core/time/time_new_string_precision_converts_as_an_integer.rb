# Time.new(string, precision:) converts the precision as an Integer: nil
# and a negative count keep every digit, a Float truncates, and a String
# is a TypeError.
p Time.new("2021-12-25 00:00:00.123456789876 +09:00").subsec
p Time.new("2021-12-25 00:00:00.123456789876 +09:00", precision: nil).subsec
p Time.new("2021-12-25 00:00:00 +09:00", precision: 0).subsec
p Time.new("2021-12-25 00:00:00.123456789876 +09:00", precision: -1).subsec
obj = Object.new; def obj.to_int = 3
p Time.new("2021-12-25 00:00:00.123456789876 +09:00", precision: 1.2).subsec
p Time.new("2021-12-25 00:00:00.123456789876 +09:00", precision: obj).subsec
p Time.new("2021-12-25 00:00:00.123456789876 +09:00", precision: 3r).subsec
p((Time.new("2021-12-25 00:00:00.123456789876 +09:00", precision: "") rescue [$!.class, $!.message]))
