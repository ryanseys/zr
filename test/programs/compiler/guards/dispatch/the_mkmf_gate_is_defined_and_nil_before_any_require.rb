# `defined?` and its `const_defined?` / `constants.include?` spellings ask
# whether a name is bound YET. A definition further down the program has not
# run, so at the guard the answer is no -- which is exactly what the
# define-it-if-nobody-else-did idiom is written for.

# The mkmf gate itself: defined, and nil, before any require -- CRuby sets
# it at the VM level. A fold that scans the program for `CROSS_COMPILING =`
# finds nothing and must still answer "constant".
p defined?(CROSS_COMPILING)
p CROSS_COMPILING

p defined?(RUBY_ENGINE)
p defined?(RUBY_VERSION)
p defined?(RUBY_PLATFORM)
p defined?(ENV)
p defined?(ARGV)
p defined?(STDOUT)
p defined?(ARGF)
p defined?(STDIN)
p defined?(STDERR)
p defined?(RUBY_PATCHLEVEL)
p defined?(RUBY_REVISION)
p defined?(RUBY_RELEASE_DATE)
p defined?(RUBY_DESCRIPTION)
p defined?(RUBY_COPYRIGHT)
p defined?(RUBY_ENGINE_VERSION)
p defined?(::RUBY_ENGINE)

if defined?(RUBY_ENGINE)
  module Engine
    KNOWN = true
  end
end
p Engine::KNOWN

