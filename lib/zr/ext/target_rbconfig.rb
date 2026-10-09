# frozen_string_literal: true

# The RbConfig of another target, for mkmf's --target-rbconfig, as
# `Ext::Builder` runs an extension's extconf.rb for that target. mkmf
# loads this file into its module (`Kernel.load path, MakeMakefile`); it
# loads the pristine rbconfig.rb of the target's ruby there
# (`ZR_TARGET_RBCONFIG`, vendor/targets/<triple>), which finds that
# ruby's headers from where it is. Then it points the tools at the
# target's cross toolchain, which the rbconfig.rb names as the target
# host does (`gcc`), and the library directory at zr's stand-in libruby
# (`ZR_TARGET_LIBDIR`), so mkmf's link checks (have_func) find the
# functions that zr's C API has.
#
# Only the host ruby loads this file, in the child that runs extconf.rb:
# it is no part of zr's runtime.

Kernel.load(ENV.fetch("ZR_TARGET_RBCONFIG"), MakeMakefile)

{ "CC" => "ZR_TARGET_CC", "CXX" => "ZR_TARGET_CXX", "AR" => "ZR_TARGET_AR", "libdir" => "ZR_TARGET_LIBDIR" }.each do |key, variable|
  value = ENV.fetch(variable, nil)
  MakeMakefile::RbConfig.fire_update!(key, value) if value && !value.empty?
end
