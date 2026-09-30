# `defined?` and its `const_defined?` / `constants.include?` spellings ask
# whether a name is bound YET. A definition further down the program has not
# run, so at the guard the answer is no -- which is exactly what the
# define-it-if-nobody-else-did idiom is written for.

# The interpreter installs a handful of constants on `Object` before the first
# line runs, and no `NAME = ...` in the program says so. Scanning for one and
# finding nothing must not read as "not defined": `defined?(RUBY_ENGINE)` is
# "constant", and a gem that gates its whole engine-compat branch on the probe
# takes the branch.
#
# Every name the runtime seeds is listed here, so a name added to one side and
# not the other shows up as a divergence rather than as a quiet nil.
%w[ARGF ARGV CROSS_COMPILING ENV RUBY_COPYRIGHT RUBY_DESCRIPTION RUBY_ENGINE
   RUBY_ENGINE_VERSION RUBY_PATCHLEVEL RUBY_PLATFORM RUBY_RELEASE_DATE
   RUBY_REVISION RUBY_VERSION STDERR STDIN STDOUT].each do |name|
  p [name, Object.const_defined?(name)]
end

