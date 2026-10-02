# frozen_string_literal: true

# The type check of the compiler: `bin/steep check` runs it, and CI runs
# it after the lint step.
#
# Types sit in the code as inline RBS (`#:` and `# @rbs`). A declaration
# that inline RBS cannot type has `# @rbs skip` above it and its type in
# sig/zr: a Struct or Data record assigned to a constant, a
# module_function module, `class << self`, constants that `const_set`
# makes. A file in RBS_TYPED has all of its types in sig/zr and is
# checked as plain Ruby. sig/vendor has the members of the gems without
# signatures that lib/ uses.
#
# lib/zr/runtime is zr's own core and kernel, compiled into each
# program, and is not checked, except the files that ruby loads too.
#
# Each file is in the first level that names it, and is checked with that
# level's diagnostics. To make a file stricter, name it (or its
# directory) in a stricter level.

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
# runtime half. Not eval/forms.rb and eval/walk_forms.rb: they define
# core methods (`Kernel#eval`, `BasicObject#instance_eval`) again, which
# RBS's core signatures already declare.
RUBY_LOADED_RUNTIME = %w[
  lib/zr/runtime/lib/zr/eval/walking.rb
  lib/zr/runtime/lib/zr/eval/runtime.rb
  lib/zr/runtime/lib/zr/obj/jit/runtime.rb
].freeze

LEVELS = {
  strict: %w[
    lib/zr/bytes.rb
    lib/zr/ir/inst.rb
    lib/zr/ir/types.rb
  ],
  default: %w[
    lib/zr/target.rb
    lib/zr/obj/model.rb
    lib/zr/load_tables.rb
    lib/zr/lower/function/loop.rb
    lib/zr/lower/function/call_site.rb
  ],
  lenient: [
    "lib/zr.rb",
    "lib/zr/*.rb",
    *(Dir.children(File.join(__dir__, "lib/zr")).sort - %w[runtime])
      .select { |name| File.directory?(File.join(__dir__, "lib/zr", name)) }
      .map { |name| "lib/zr/#{name}" },
    *RUBY_LOADED_RUNTIME,
  ],
}.freeze

# A def with no annotation takes the type of the method that it
# overrides, so an `initialize(a, b)` takes Object's `() -> void`. In a
# lenient file that only tells that the def has no annotation yet.
PRESETS = {
  strict: D::Ruby.strict,
  default: D::Ruby.default,
  lenient: D::Ruby.lenient.merge(D::Ruby::MethodParameterMismatch => :hint),
}.freeze

target :lib do
  signature "sig/zr", "sig/vendor"
  library "digest", "json", "socket", "etc", "open3", "fileutils", "pathname", "tempfile", "securerandom", "zlib", "prism"

  LEVELS.each do |level, paths|
    group level do
      check(*paths, inline: true)
      ignore(*RBS_TYPED, inline: true)
      check(*RBS_TYPED.select { |file| paths.any? { |path| file == path || file.start_with?("#{path}/") } })
      # `STEEP_LEVEL=strict bin/steep check lib/zr/ir` tells what a
      # promotion of lib/zr/ir would report.
      configure_code_diagnostics(PRESETS.fetch(ENV.fetch("STEEP_LEVEL", level).to_sym))
    end
  end
end
