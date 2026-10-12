# The shapes of the version constants, and a self-consistency check that
# RUBY_DESCRIPTION is composed from its parts as CRuby's version.c composes
# it: "ruby <version><stage> (<date> <branch> <revision>) +PRISM [<platform>]",
# where a preview names its stage ("preview1") and its branch ("master") and
# a release says "revision". Portable across rubies and build hosts.

puts RUBY_VERSION.match?(/\A\d+\.\d+\.\d+\z/)
puts RUBY_ENGINE
puts RUBY_PATCHLEVEL.is_a?(Integer)
puts File::SEPARATOR
p File::ALT_SEPARATOR
short = RUBY_REVISION[0, 10]
composed = /\Aruby #{Regexp.escape(RUBY_VERSION)}(?:preview|rc)?\d* \(#{RUBY_RELEASE_DATE} (?:revision|master) #{short}\) \+PRISM (?:\+\w+ )*\[#{Regexp.escape(RUBY_PLATFORM)}\]\z/
puts composed.match?(RUBY_DESCRIPTION)
# A development build (patch level -1) names its branch; a release does not.
puts RUBY_DESCRIPTION.include?(" revision ") == (RUBY_PATCHLEVEL >= 0)
