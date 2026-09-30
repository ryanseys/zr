# Stable values plus a self-consistency check that RUBY_DESCRIPTION is
# composed from its parts exactly as CRuby's version.c does (portable
# across build hosts; RUBY_PLATFORM is derived from the build target).

puts RUBY_VERSION
puts RUBY_ENGINE
puts RUBY_PATCHLEVEL
puts File::SEPARATOR
p File::ALT_SEPARATOR
short = RUBY_REVISION[0, 10]
composed = "ruby #{RUBY_VERSION} (#{RUBY_RELEASE_DATE} revision #{short}) +PRISM [#{RUBY_PLATFORM}]"
puts RUBY_DESCRIPTION == composed
