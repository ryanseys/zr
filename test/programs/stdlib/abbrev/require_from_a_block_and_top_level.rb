# The SAME file required from inside a block AND at top level. The first
# require runs the file body, so a constant assigned in the module body
# exists after both requires. The second require only returns false.
#
# `gems/time/lib/time.rb` shows the same shape with `Time::ZoneOffset`.
# This test uses `abbrev`, the smallest vendored gem with a module-body
# constant.
[1].each do
  require "abbrev"
  p Abbrev::VERSION
end

require "abbrev"
p Abbrev::VERSION
p Abbrev.abbrev(["ruby"])["rub"]
