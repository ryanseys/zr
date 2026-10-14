# frozen_string_literal: true

# The type check of the compiler: `bin/steep check` runs it, and CI runs
# it after the lint step.
#
# Types sit in the code as inline RBS (`#:` and `# @rbs`). A declaration
# that inline RBS cannot type has `# @rbs skip` above it and its type in
# sig/zr: a Struct or Data record assigned to a constant, `class <<
# self`, constants that `const_set` makes, an include whose constants a
# class reads (docs/explanation/ruby-style.md, "Types"). A file in RBS_TYPED has all of its types in sig/zr and is
# checked as plain Ruby. sig/vendor has the members of the gems without
# signatures that lib/ uses.
#
# lib/zr/runtime is zr's own core and kernel, compiled into each
# program, and is not checked here, except the files that ruby loads
# too. The `kernel` target checks the kernel, one layer at a time.
#
# Each file is in the first level that names it, and is checked with that
# level's diagnostics. All files are strict, except the two record
# files in `default`, which hit limits of Steep.

D = Steep::Diagnostic

# The files typed wholly in sig/zr.
RBS_TYPED = %w[
  lib/zr/hir/node.rb
  lib/zr/obj/model.rb
  lib/zr/load_tables.rb
  lib/zr/lower/function/loop.rb
  lib/zr/lower/function/call_site.rb
].freeze

# The runtime files that ruby loads: the eval interpreter and the JIT's
# runtime half. Not eval/forms.rb and eval/interpreter_forms.rb: they define
# core methods (`Kernel#eval`, `BasicObject#instance_eval`) again, which
# RBS's core signatures already declare.
RUBY_LOADED_RUNTIME = %w[
  lib/zr/runtime/lib/zr/eval/world.rb
  lib/zr/runtime/lib/zr/eval/runtime.rb
  lib/zr/runtime/lib/zr/obj/jit/runtime.rb
].freeze

LEVELS = {
  # hir/node.rb: Steep types `X = Node.new(...)` as a Node, not a class.
  # obj/model.rb: Steep checks `**options` against the keywords of the
  # record that gets them.
  default: %w[lib/zr/hir/node.rb lib/zr/obj/model.rb],
  strict: [
    "lib/zr.rb",
    "lib/zr/*.rb",
    *(Dir.children(File.join(__dir__, "lib/zr")).sort - %w[runtime])
      .select { |name| File.directory?(File.join(__dir__, "lib/zr", name)) }
      .map { |name| "lib/zr/#{name}" },
    *RUBY_LOADED_RUNTIME,
  ],
}.freeze

PRESETS = {
  strict: D::Ruby.strict,
  default: D::Ruby.default,
}.freeze

target :lib do
  signature "sig/zr", "sig/vendor"
  library "digest", "json", "socket", "etc", "open3", "fileutils", "pathname", "tempfile", "securerandom", "shellwords", "zlib", "prism"

  LEVELS.each do |level, paths|
    group level do
      check(*paths, inline: true)
      ignore(*RBS_TYPED, inline: true)
      check(*RBS_TYPED.select { |file| paths.any? { |path| File.fnmatch?(path, file) || file.start_with?("#{path}/") } })
      # `STEEP_LEVEL=default bin/steep check` checks every file at one level.
      configure_code_diagnostics(PRESETS.fetch(ENV.fetch("STEEP_LEVEL", level).to_sym))
    end
  end
end

# The kernel of one target, at the strict level, with sig/zr/kern.rbs:
# the portable files, the OS layer that ZR_KERNEL_OS names (darwin,
# linux or wasi; this host's by default) and its architecture layer.
# Steep checks a file in one target only, and the layers share the
# portable files, so one check has one layer:
# `ZR_KERNEL_OS=wasi bin/steep check --group=kernel` checks another.
KERNEL_LAYERS = { "darwin" => "aarch64", "linux" => "aarch64", "wasi" => "wasm32" }.freeze
KERNEL_OS = ENV.fetch("ZR_KERNEL_OS") { RUBY_PLATFORM.include?("darwin") ? "darwin" : "linux" }

target :kernel do
  kernel = "lib/zr/runtime/kernel"
  signature "sig/zr/kern.rbs"
  check "#{kernel}/*.rb", "#{kernel}/os/#{KERNEL_OS}", "#{kernel}/arch/#{KERNEL_LAYERS.fetch(KERNEL_OS)}", inline: true
  configure_code_diagnostics(D::Ruby.strict)
end
