# The north star is byte-for-byte MRI parity, so the engine-identity
# constants report CRuby's own: RUBY_ENGINE == "ruby", RUBY_ENGINE_VERSION
# == RUBY_VERSION, and RUBY_DESCRIPTION takes version.c's exact banner
# (`ruby <ver>[<stage>] (<date> <branch> <short-rev>) +PRISM [<platform>]`).

puts RUBY_ENGINE
puts RUBY_ENGINE_VERSION == RUBY_VERSION
puts RUBY_DESCRIPTION.start_with?("ruby #{RUBY_VERSION}")
puts RUBY_DESCRIPTION.include?("+PRISM")
