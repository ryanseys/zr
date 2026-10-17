# Gem::Specification lists the gems that ruby's install has: its default
# gems and its bundled gems, whether or not the program requires them.
names = Gem::Specification.map(&:name)
%w[abbrev prime rake minitest test-unit fileutils json].each { |name| p [name, names.include?(name)] }
p Gem::Specification.find_by_name("prime").version.to_s
p Gem::Specification.find_by_name("fileutils").default_gem?
p Gem.loaded_specs.key?("prime")
