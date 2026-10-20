def t(l) = (puts "#{l}: #{yield.inspect}" rescue puts "#{l}: #{$!.class}: #{$!.message}")
t("str Z") { x = Time.new("2026-02-30 00:00:00Z"); [x.year, x.month, x.day, x.to_i, x.inspect, x.wday, x.yday, x.utc?] }
t("args Z") { x = Time.new(2026, 2, 30, 0, 0, 0, "Z"); [x.month, x.day, x.to_i, x.to_a] }
t("args UTC") { x = Time.new(2026, 2, 30, 0, 0, 0, "UTC"); [x.month, x.day, x.to_i, x.zone] }
t("args 0") { x = Time.new(2026, 2, 30, 0, 0, 0, 0); [x.month, x.day, x.to_i] }
t("off -5") { x = Time.new("2026-02-31 23:00:00 -05:00"); [x.month, x.day, x.to_i, x.inspect] }
t("off +9") { x = Time.new(2026, 2, 30, 1, 0, 0, "+09:00"); [x.month, x.day, x.hour, x.to_i, x.inspect] }
t("off +9 late") { x = Time.new(2026, 2, 29, 23, 0, 0, "+09:00"); [x.month, x.day, x.hour, x.to_i, x.inspect] }
t("jun31") { Time.new("2026-06-31 12:00:00Z").inspect }
t("utc") { x = Time.utc(2026, 2, 30); [x.month, x.day] }
t("local") { x = Time.new(2026, 2, 30); [x.month, x.day] }
t("gm +") { x = Time.new(2026, 2, 30, 0, 0, 0, "Z") + 1; [x.month, x.day] }
t("feb29 leap") { x = Time.new(2024, 2, 30, 0, 0, 0, "Z"); [x.month, x.day, x.to_i] }
t("feb 31 Z strftime") { Time.new(2026, 2, 31, 0, 0, 0, "Z").strftime("%F %j %a") }
t("getutc") { Time.new(2026, 2, 30, 0, 0, 0, "+01:00").getutc.inspect }
t("in:") { x = Time.new(2026, 2, 30, 0, 0, 0, in: "Z"); [x.month, x.day] }
t("apr31 -1") { x = Time.new(2026, 4, 31, 0, 30, 0, "-01:00"); [x.month, x.day, x.hour, x.to_i] }
t("dec32") { Time.new(2026, 12, 32, 0, 0, 0, "Z") }
t("valid ctime") { x = Time.new(2026, 3, 2, 0, 0, 0, "Z"); [x.ctime, x.to_s, x.inspect, x.strftime("%c %a"), x.ctime] }
t("wrap 24") { x = Time.new(2026, 2, 30, 24, 0, 0, "Z"); [x.month, x.day, x.hour, x.to_i, x.inspect] }
t("wrap 24 31") { x = Time.new(2026, 2, 31, 24, 0, 0, "Z"); [x.month, x.day, x.hour, x.to_i, x.inspect] }
t("wrap dec") { x = Time.new(2026, 12, 31, 24, 0, 0, "Z"); [x.year, x.month, x.day, x.to_a, x.wday] }
t("order") { x = Time.new(2026, 2, 30, 0, 0, 0, "Z"); a = [x.month, x.day]; x.wday; a + [x.month, x.day, x.inspect] }
t("strftime fills") { x = Time.new(2026, 2, 30, 0, 0, 0, "Z"); x.strftime("%F"); [x.month, x.day] }
t("copies") { x = Time.new(2026, 2, 31, 0, 0, 0, "Z"); [x.getlocal("-05:00").day, x.utc.day, x.gmtime.day, x.getgm.month, x.dup.day, (x + 0).day, x.round.day, Marshal.load(Marshal.dump(x)).day] }
t("dup wday") { x = Time.new(2026, 2, 31, 0, 0, 0, "Z"); y = x.dup; [y.wday, x.day, y.day] }
t("frozen") { x = Time.new(2026, 2, 30, 0, 0, 0, "Z").freeze; [x.wday, x.day] }
t("xmlschema") { x = Time.new(2026, 2, 30, 0, 0, 0, "Z"); [x.iso8601, x.xmlschema(2)] }
t("off -5 31 22") { x = Time.new(2026, 4, 31, 22, 0, 0, "-05:00"); [x.month, x.day, x.to_i] }
t("off -00:30") { x = Time.new(2026, 2, 31, 23, 45, 0, "-00:30"); [x.month, x.day, x.hour, x.to_i] }
t("off -30s 24") { x = Time.new(2026, 2, 31, 24, 0, 0, -30); [x.month, x.day, x.hour, x.to_i] }
t("off rational") { x = Time.new(2026, 2, 31, 23, 59, 59.5r, -0.5r); [x.month, x.day, x.to_r] }
t("off +5") { x = Time.new(2026, 2, 31, 2, 0, 0, "+05:00"); [x.month, x.day, x.to_i] }
t("dec31 off") { x = Time.new(2026, 12, 31, 23, 0, 0, "-05:00"); [x.year, x.month, x.day] }
t("sunday") { x = Time.new(2026, 2, 30, 0, 0, 0, "Z"); [x.monday?, x.day] }
t("deconstruct") { Time.new(2026, 2, 30, 0, 0, 0, "Z").deconstruct_keys(nil) }
t("cmp") { [Time.new(2026, 2, 31, 0, 0, 0, "Z") <=> Time.utc(2026, 3, 3), Time.new(2026, 2, 31, 0, 0, 0, "Z").hash == Time.utc(2026, 3, 3).hash] }
t("year day") { x = Time.new(2026, 2, 30, 0, 0, 0, "Z"); [x.yday, x.day] }
