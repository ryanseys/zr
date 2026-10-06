# ruby loads rubygems before a program's first line: Gem answers without
# a require, `require "rubygems"` answers false, and Kernel#require and
# #gem are rubygems' own. A String compares with a Gem::Version through
# the version's own <=>.
p defined?(Gem), require("rubygems"), $LOADED_FEATURES.any? { |feature| feature.end_with?("/rubygems.rb") }
p Kernel.private_instance_methods.include?(:gem), Kernel.private_instance_methods.include?(:gem_original_require)
p Gem::Version.new("1.10") > Gem::Version.new("1.9"), "9.0" < Gem::Version.new("10.0")
p Gem.loaded_specs.class, Gem::Requirement.new("~> 1.2").satisfied_by?(Gem::Version.new("1.5"))
p Gem::Platform.local.os.empty?

