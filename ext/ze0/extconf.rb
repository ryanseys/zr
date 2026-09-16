# frozen_string_literal: true

# ze0 has no C extension. RubyGems runs this file as a gem installs, and
# ze0 uses the step to build the vendored C (prism and oniguruma) into
# the gem's vendor/build, while the gem's directory can still be written.
# A native binary links against those archives.
#
# A host that cannot link a native binary gets a Makefile that builds
# nothing, and the install goes on: wasm modules and Mach-O objects need
# no archives.
#
# `make clean` and `make install` do nothing: RubyGems runs them around
# the build, and neither may remove what it made.

require "rbconfig"
require_relative "../../lib/ze0/target"

lib = File.expand_path("../../lib", __dir__)
target = Ze0::Target.default
recipe = if target.linkable? && target.roads.include?(:native)
           ruby = RbConfig.ruby
           %(\t"#{ruby}" -I"#{lib}" -rze0/deps -e 'puts Ze0::Deps.build(Ze0::Target.fetch("#{target.triple}"))')
         else
           why = target.refusal(nil)
           %(\t@echo "ze0: the vendored archives are not built: #{why.gsub('"', '\\"')}")
         end

File.write("Makefile", <<~MAKE)
  all:
  #{recipe}

  install:

  clean:

  .PHONY: all install clean
MAKE
