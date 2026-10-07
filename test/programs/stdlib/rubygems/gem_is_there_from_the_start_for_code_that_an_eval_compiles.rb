# ruby loads rubygems before a program's first line, so Gem and its names
# are there for code that an eval compiles, in any scope, and a require of
# rubygems or bundled_gems returns false. Only the eval strings name Gem.
names = %i[Gem RUBYGEMS_ACTIVATION_MONITOR]
p names.map { |name| Object.const_defined?(name) }
p names.all? { |name| Object.constants.include?(name) }
p eval("module LazyGemProbe; class << self; extend Gem::Deprecate; end; end; :ok")
p eval("require 'rubygems'"), eval("require 'bundled_gems'")
p eval("Gem::Version.new('2') > Gem::Version.new('10')")
p eval("Gem::VERSION.class"), eval("RUBYGEMS_ACTIVATION_MONITOR.class")
p Object.autoload?(:Gem), Object.autoload?(:RUBYGEMS_ACTIVATION_MONITOR)
p $LOADED_FEATURES.count { |path| path.end_with?("/rubygems.rb") }
p $LOADED_FEATURES.grep(%r{/zr/rubygems\.rb\z}).size
