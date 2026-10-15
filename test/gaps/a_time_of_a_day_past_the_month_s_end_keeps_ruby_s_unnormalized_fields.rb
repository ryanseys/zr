# Time.new of a day past the end of its month (Feb 30) is CRuby's time.c
# quirk: in UTC the Time keeps the fields as given, so it shows Feb 30
# though its epoch second is Mar 2. A fixed offset moves it through
# vtm_add_offset, which lands a month early. zr normalizes the date, as
# Time.utc and a local time do in both.
p Time.new("2026-02-30 00:00:00Z").day
p Time.new(2026, 2, 30, 0, 0, 0, "Z").month
p Time.new("2026-02-31 23:00:00 -05:00").to_i
p Time.new("2026-06-31 12:00:00Z").inspect
