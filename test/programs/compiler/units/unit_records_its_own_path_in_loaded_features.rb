# `$LOADED_FEATURES` names the FILE a require loaded, never the spelling the
# require asked under. CRuby lists absolute paths, and real libraries read that
# list: rubygems' `already_loaded?` compares `"#{load_path_entry}/#{file}"`
# against it, and bundler's `shared_helpers` asks each entry
# `start_with?(resolved_path)`.
#
# A compiled-in unit also records its source file path, not the short name
# that the require used.

require_relative "unit_loaded_features/part" if ENV["NEVER"]

def load_part
  require_relative "unit_loaded_features/part"
end

load_part
entry = $LOADED_FEATURES.last
p entry.start_with?("/")
p File.basename(entry)
p File.exist?(entry)
# One entry per FILE, however many spellings reach it.
p $LOADED_FEATURES.count { |f| File.basename(f) == "part.rb" }
