# `strftime`'s directive table, including Ruby's `-`/`_` padding flags and
# the verbatim-unknown-directive rule.

t = Time.at(1700000000).getutc
puts t.strftime("%Y-%m-%d %H:%M:%S")
puts t.strftime("%F %T")
puts t.strftime("%a %A %b %B")
puts t.strftime("%j %u %w %p %I")
puts t.strftime("%z %Z")
puts t.strftime("%y %C %s")
puts t.strftime("100%% literal")
puts t.strftime("%Q")
jan = Time.at(1704067200).getutc
puts jan.strftime("%m|%-m|%_m")
