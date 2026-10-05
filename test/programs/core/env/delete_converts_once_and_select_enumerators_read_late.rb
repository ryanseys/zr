# ENV.delete converts its name once. ENV.select, filter and reject with no
# block read the variables when the Enumerator runs.
ENV["ZRFOO"] = "bar"
k = Object.new
def k.to_str = (($n ||= 0); $n += 1; "ZRFOO")
p ENV.delete(k), $n, ENV["ZRFOO"]
en = ENV.select
fi = ENV.filter
ENV["ZRFOO2"] = "x"
p en.each { |a, _| a == "ZRFOO2" }, fi.each { |a, _| a == "ZRFOO2" }
p ENV.reject.each { |a, _| a != "ZRFOO2" }
