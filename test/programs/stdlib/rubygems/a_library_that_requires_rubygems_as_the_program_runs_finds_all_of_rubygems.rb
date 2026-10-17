# ruby loads rubygems before the program's first line. A library that
# requires it as the program runs (RDoc::Options.new requires rdoc/rdoc,
# which requires rubygems) gets false and all of rubygems: in zr, where
# `Gem` is an autoload until the program uses it, as well.
eval("1")
require "rdoc"
p RDoc::Options.new.class
p %w[rubygems bundled_gems].map { |name| $LOADED_FEATURES.any? { it.end_with?("/#{name}.rb") } }
p Object.autoload?(:Gem)
p Gem::Specification, Gem::MissingSpecError.ancestors.include?(Gem::LoadError)
p require("rubygems"), Gem::Version.new("1.2") < Gem::Version.new("1.10")
