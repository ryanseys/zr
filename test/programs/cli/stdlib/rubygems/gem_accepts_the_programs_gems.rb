# `gem` in a binary answers as under `bundle exec`: rubygems knows the
# gems that the build compiled in (the gem manifest), and no others.
#
# Only the answers that ruby and a zr binary share. Ruby activates its
# own default json and searches its gem directories; the binary finds
# json in its manifest and has no gem directory. Both accept json with
# no requirement, and both raise Gem::LoadError for a gem or a version
# that they do not have.

require "json"

p gem("json")
p Gem.loaded_specs.key?("json")

[["json", ">= 99"], ["zr-no-such-gem"], ["zr-no-such-gem", "~> 1.0"]].each do |args|
  gem(*args)
  puts "#{args.inspect}: activated"
rescue Gem::LoadError => e
  puts "#{args.inspect}: #{e.class.ancestors.include?(Gem::LoadError)} #{e.name}"
end
