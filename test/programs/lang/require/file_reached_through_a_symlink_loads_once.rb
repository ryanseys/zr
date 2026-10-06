# A require keys a file by its real path too, as CRuby's
# loaded_features_realpaths does: the same file reached again through a
# symlinked $LOAD_PATH directory runs no second time, and
# $LOADED_FEATURES keeps the first spelling. A require that fails leaves
# out only its own file; what it required on the way stays loaded.

base = File.join(__dir__, "symlinked_file")
require_relative "symlinked_file/lib/alpha"
$LOAD_PATH.unshift File.join(base, "linked")
p require("alpha"), Alpha::LOADS
p $LOADED_FEATURES.grep(/alpha/).map { |f| f.delete_prefix(base) }

begin
  require_relative "symlinked_file/lib/fails"
rescue => e
  p e.message
end
p $LOADED_FEATURES.grep(/fails|beta/).map { |f| f.delete_prefix(base) }
p require("deep/beta")

