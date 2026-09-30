# A require of a feature already loaded reads no file, so ruby keeps
# no autoload row for one -- `autoload?` answers nil. It declares
# the name all the same, and on any module but Object that is
# visible: the name stands among the constants, and a read of it
# finds nothing there rather than the constant further out.
#
# rb_const_defined_0 stops at that row and answers false, where
# rb_const_search_from passes over it and reads on, so
# `const_defined?` and a read part company on the same name.
require "csv"

module Holder; end
Holder.autoload(:CSV, "csv")

p Holder.autoload?(:CSV)
p Holder.constants
p Holder.const_defined?(:CSV)
p Holder.const_get(:CSV).to_s
begin
  Holder::CSV
rescue NameError => e
  puts e.message
end
module Holder
  p CSV.to_s
  p defined?(CSV)
end
