# Time.gm's seventh argument is microseconds only among seven, a string
# time checks each field's range, xmlschema writes past nine digits from
# the exact fraction, and Marshal.load drops an offset or zone it cannot
# use and keeps a zone name across +.
def t(l)
  p [l, yield]
rescue StandardError => e
  p [l, e.class, e.message]
end
ENV["TZ"] = "UTC"
t(:gm10) { Time.gm(0, 0, 0, 1, 1, 2000, :foo, :bar, false, :baz) }
t(:gm_str_mon) { Time.gm(2000, "jan") }
t(:gm_str_sec) { Time.gm(2000, 1, 1, 0, 0, "0", :foo, :foo) }
t(:gm_str_zone) { Time.gm(2000, 1, 1, 0, 0, 0, "0") }
t(:new_sec64) { Time.new("2020-12-25 00:56:64 +0900") }
x = Time.at(2.quo(3)).getlocal("+09:00")
t(:xml10) { x.xmlschema(10) }
t(:xml20) { x.xmlschema(20) }
data = "\x04\bIu:\tTime\r\xEFF\x1C\x80\x00\x00\x00\x00\x06:\voffset"
t(:broken_offset) { [Marshal.load(data + "T").utc_offset, Marshal.load(data + "\"\x0ebadoffset").utc_offset] }
zdata = "\x04\bIu:\tTime\r\xEFF\x1C\x80\x00\x00\x00\x00\x06:\tzone"
t(:broken_zone) { [Marshal.load(zdata + "T").zone, Marshal.load(zdata + "\"\b\0\0\0").zone] }
ENV["TZ"] = "JST-9"
lt = Marshal.load(Marshal.dump(Time.local(2013, 2, 24)))
t(:zone) { [lt.zone, (lt + 1).zone, Time.local(2013, 2, 24).zone] }
