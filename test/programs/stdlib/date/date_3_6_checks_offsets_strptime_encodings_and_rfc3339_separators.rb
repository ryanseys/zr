# date 3.6.0 (ruby 4.1): an offset past a day is ignored (0, with a
# warning under -w), also an integral Rational one. _strptime checks that
# the text and the format have compatible encodings. Date._rfc3339 warns
# about a separator other than T or a space under Warning[:deprecated].
$stderr = $stdout
require "date"
def t(label)
  p [label, yield]
rescue Exception => e
  p [label, e.class, e.message]
end
t(:incompat) { Date._strptime("2001 é", "%Y é".encode("ISO-8859-1")) }
t(:fmt_int) { Date._strptime("2001".encode("UTF-16LE"), 1) }
t(:str_utf16) { Date._strptime("2001".encode("UTF-16LE"), "%Y") }
t(:fmt_utf16) { Date._strptime("2001", "%Y".encode("UTF-16LE")) }
t(:binary_zone) { h = Date._strptime("2001 JST é".b, "%Y %Z"); [h[:zone].encoding, h[:leftover].encoding] }
t(:emoji) { DateTime._strptime("2011-10-05T22:26:12\u{2600 fe0f}") }
t(:emoji_date) { Date._strptime("2011-10-05\u{2600}") }
t(:ascii_both) { Date._strptime("2001 x".b, "%Y x") }
t(:sjis_fmt) { Date._strptime("2001", "%Y".encode("Shift_JIS")) }
t(:euc_utf8) { Date._strptime("2001 é".encode("EUC-JP"), "%Y é") }
t(:strptime_incompat) { Date.strptime("2001 é", "%Y é".encode("ISO-8859-1")) }
t(:datetime) { DateTime._strptime("2001 é", "%Y é".encode("ISO-8859-1")) }
Warning[:deprecated] = true
t(:rfc_tab) { Date._rfc3339("2001-02-03\t04:05:06+07:00") }
t(:rfc_space) { Date._rfc3339("2001-02-03 04:05:06+07:00") }
t(:rfc_t) { Date._rfc3339("2001-02-03t04:05:06+07:00") }
t(:rfc_nl) { DateTime.rfc3339("2001-02-03\n04:05:06+07:00").to_s }
t(:rfc_cr) { Date.rfc3339("2001-02-03\r04:05:06+07:00").to_s }
Warning[:deprecated] = false
t(:rfc_quiet) { Date._rfc3339("2001-02-03\t04:05:06+07:00") }
$VERBOSE = true
[2, 1, -1, 0, Rational(2, 1), Rational(1, 1), Rational(-1, 1), Rational(1, 2), Rational(49710, 1), Rational(1, 86400 * 3), 1.5, 0.5, 0.25, 1.0, -1.0, 2.0, "+09:00", "+25:00", "junk", "Z", "+24:00", "-24:00", "+24:01", 0.123456789, 2**70, 1i].each do |of|
  t([:new, of]) { DateTime.new(2024, 1, 1, 0, 0, 0, of).offset }
  t([:new_offset, of]) { DateTime.new(2024).new_offset(of).offset }
end
t(:jd) { DateTime.jd(0, 0, 0, 0, Rational(2, 1)).offset }
t(:ordinal) { DateTime.ordinal(2024, 1, 0, 0, 0, Rational(2, 1)).offset }
t(:commercial) { DateTime.commercial(2024, 1, 1, 0, 0, 0, Rational(2, 1)).offset }
t(:time_to_datetime) { Time.at(0, in: "+09:00").to_datetime.offset }
