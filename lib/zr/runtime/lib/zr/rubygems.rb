# frozen_string_literal: true

# The autoload of Gem: rubygems, bundled_gems and the program's gems, in
# the order of the prelude that loads them as a program boots
# (Hir::Preludes.rubygems).
require "rubygems"
require "bundled_gems"
require "zr/gem_manifest"
