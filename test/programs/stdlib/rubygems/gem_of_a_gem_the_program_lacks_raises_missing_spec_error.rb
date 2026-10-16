# `gem` of a gem that is not installed raises rubygems' own
# Gem::MissingSpecError, a LoadError that names the gem and the
# requirement, and counts the gems it knows.
[["zr_no_such_gem"], ["zr_no_such_gem", "~> 1.2"], ["zr_no_such_gem", ">= 1", "< 3"]].each do |args|
  gem(*args)
rescue LoadError => e
  p [e.class, e.class.ancestors.take_while { |c| c != Object }, e.name, e.requirement.to_s]
  puts e.message.lines.first.sub(/among \d+ total/, "among N total")
end
