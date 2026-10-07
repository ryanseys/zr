# The autoload of Gem (zr/gem_autoload.rb): rubygems, bundled_gems and the
# program's gems, in the order of the prelude that loads them as a program
# boots (Hir::Build.rubygems).
require "rubygems"
require "bundled_gems"
require "zr/gem_manifest"
