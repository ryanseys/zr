# Time.new of a day past the end of its month (Feb 30) keeps CRuby's
# time.c fields: in UTC the Time shows Feb 30, though its epoch second
# is Mar 2, and a negative fixed offset carries the 31st to a 32nd that
# the 5 bits of mday hold as 0, a month early.
p Time.new("2026-02-30 00:00:00Z").day
p Time.new(2026, 2, 30, 0, 0, 0, "Z").month
p Time.new("2026-02-31 23:00:00 -05:00").to_i
p Time.new("2026-06-31 12:00:00Z").inspect
