# A fraction of the last day part moves a constructed date on, a Rational
# step keeps its fraction of a nanosecond, the default formats and the
# zone are US-ASCII, and %:::z parses as date_strptime.c reads it.
require "date"
def t(label)
  print label, ": "
  p yield
rescue Exception => e
  p [e.class, e.message]
end
t("jd 2451944.5") { Date.jd(2451944.5).jd }
t("jd 2451944.5 dt") { DateTime.jd(2451944.5).then { [_1.jd, _1.hour] } }
t("jd Rational 2451944.5") { Date.jd(Rational("2451944.5")).jd }
t("civil 3.5") { Date.civil(2001, 2, 3.5).then { [_1.year, _1.mon, _1.mday, _1.day_fraction] } }
t("ordinal 2.5") { Date.ordinal(2001, 2.5).then { [_1.yday, _1.day_fraction] } }
t("commercial 3.5") { Date.commercial(2001, 2, 3.5).then { [_1.cwday, _1.day_fraction] } }
t("jd 2451944.5 frac") { Date.jd(2451944.5).day_fraction }
t("jd 1.5 class") { Date.jd(1.5).class }
s = "\x04\bU:\tDate[\bU:\rRational[\ai\x03\xCF\xD3Ji\ai\x00o:\x13Date::Infinity\x06:\a@di\xFA"
t("m192 date") { d = Marshal.load(s); [d.ajd, d.start, d.to_s, d.jd] }
s = "\x04\bU:\rDateTime[\bU:\rRational[\al+\b\xC9\xB0\x81\xBD\x02\x00i\x02\xC0\x12U;\x06[\ai\bi\ro:\x13Date::Infinity\x06:\a@di\xFA"
t("m192 datetime") { d = Marshal.load(s); [d.ajd, d.offset, d.start, d.to_s] }
t("zone enc") { DateTime.new(2001, 2, 3).zone.encoding }
t("to_s enc") { [Date.new(2001, 2, 3).to_s.encoding, Date.new(2001, 2, 3).strftime.encoding, DateTime.new(2001, 2, 3).to_s.encoding, DateTime.new(2001, 2, 3).strftime.encoding] }
t("inspect enc") { [Date.new(2001, 2, 3).inspect.encoding, DateTime.new(2001, 2, 3).inspect.encoding] }
t("iso8601 enc") { [Date.new(2001, 2, 3).iso8601.encoding, DateTime.new(2001, 2, 3).iso8601.encoding, Date.new(2001,2,3).httpdate.encoding, Date.new(2001,2,3).jisx0301.encoding] }
t("strftime fmt enc") { [Date.new(2001, 2, 3).strftime("%Y".encode("UTF-8")).encoding, Date.new(2001, 2, 3).strftime("%Y".b).encoding] }
t("to_time subsec") { (DateTime.new(2004, 9, 19, 1, 2, 3, 0) + 456789123456789123.to_r/86400000000000000000000).to_time.utc.then { [_1.sec, _1.subsec] } }
t("to_time subsec offset") { (DateTime.new(2004, 9, 19, 1, 2, 3, Rational(9, 24)) + Rational(1, 3 * 86400)).to_time.then { [_1.sec, _1.subsec, _1.utc_offset] } }
t("sec_fraction") { (DateTime.new(2004, 9, 19, 1, 2, 3, 0) + 456789123456789123.to_r/86400000000000000000000).sec_fraction }
t("strptime %:::z") { Date._strptime("+00", "%:::z") }
t("strptime %:::z 2") { ["+09", "-05", "+09:30", "+0930", "Z", "+0", "+090000"].map { |z| Date._strptime(z, "%:::z") } }
t("strptime %::z") { ["+09:30:15", "+09", "+0930"].map { |z| Date._strptime(z, "%::z") } }
t("strptime %:z") { ["+09:30", "+09", "+0930"].map { |z| Date._strptime(z, "%:z") } }
t("strptime fails") { [Date._strptime("%:x", "%:x"), Date._strptime("+09", "%::::z"), Date._strptime("x", "%:")] }
