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
    lib/zr.rb
    lib/zr/backend.rb
    lib/zr/backend/aarch64.rb
    lib/zr/backend/aarch64/registers.rb
    lib/zr/backend/aarch64/stub.rb
    lib/zr/backend/wasm.rb
    lib/zr/bytes.rb
    lib/zr/cache/janitor.rb
    lib/zr/cache/kernel.rb
    lib/zr/cache/lowering/core.rb
    lib/zr/cache/lowering/eval_support.rb
    lib/zr/cli.rb
    lib/zr/cli/command.rb
    lib/zr/cli/commands/diff.rb
    lib/zr/cli/commands/doctor.rb
    lib/zr/cli/commands/gems.rb
    lib/zr/cli/commands/help.rb
    lib/zr/cli/commands/inspect.rb
    lib/zr/cli/commands/version.rb
    lib/zr/cli/errors.rb
    lib/zr/cli/help.rb
    lib/zr/cli/refusals.rb
    lib/zr/diff.rb
    lib/zr/doctor.rb
    lib/zr/eval_support.rb
    lib/zr/gc_tuning.rb
    lib/zr/gem_set/resolve.rb
    lib/zr/hir/build/coverage.rb
    lib/zr/hir/dump.rb
    lib/zr/hir/escape.rb
    lib/zr/hir/features.rb
    lib/zr/hir/locals.rb
    lib/zr/hir/preludes.rb
    lib/zr/hir/syntax_report.rb
    lib/zr/host.rb
    lib/zr/ir.rb
    lib/zr/ir/analysis.rb
    lib/zr/ir/effects.rb
    lib/zr/ir/fingerprint.rb
    lib/zr/ir/function.rb
    lib/zr/ir/inst.rb
    lib/zr/ir/mem2reg.rb
    lib/zr/ir/promotion.rb
    lib/zr/ir/regions.rb
    lib/zr/ir/statics.rb
    lib/zr/ir/switches.rb
    lib/zr/ir/threads.rb
    lib/zr/ir/types.rb
    lib/zr/ir/verify.rb
    lib/zr/library.rb
    lib/zr/library
    lib/zr/load_tables.rb
    lib/zr/lower.rb
    lib/zr/lower/function/call_site.rb
    lib/zr/lower/function/loop.rb
    lib/zr/machine/host/memory.rb
    lib/zr/native/link.rb
    lib/zr/native/link
    lib/zr/native/resident.rb
    lib/zr/obj/jit.rb
    lib/zr/obj/jit/fiddle.rb
    lib/zr/obj/macho/libsystem.rb
    lib/zr/obj/macho/skeleton.rb
    lib/zr/obj/macho/stamps.rb
    lib/zr/obj/relocs/aarch64.rb
    lib/zr/obj/string_table.rb
    lib/zr/parse.rb
    lib/zr/prism_shim
    lib/zr/refused.rb
    lib/zr/runtime.rb
    lib/zr/runtime_sources.rb
    lib/zr/server/client.rb
    lib/zr/session.rb
    lib/zr/source_guard.rb
    lib/zr/symbol_numbering.rb
    lib/zr/target.rb
    lib/zr/version.rb
    lib/zr/runtime/lib/zr/eval/walking.rb
    lib/zr/runtime/lib/zr/obj/jit/runtime.rb
  ],
  # hir/node.rb: Steep types `X = Node.new(...)` as a Node, not a class.
  # obj/model.rb: Steep checks `**options` against its keywords.
  default: %w[
    lib/zr/hir/node.rb
    lib/zr/obj/model.rb
    lib/zr/hir/build/patterns.rb
    lib/zr/hir/build/requires.rb
    lib/zr/ir/gvn.rb
    lib/zr/lower/function/sends/arith.rb
    lib/zr/lower/function/sends/in_place.rb
    lib/zr/lower/function/tracing.rb
    lib/zr/machine/description.rb
    lib/zr/machine/host/walk/regexps.rb
    lib/zr/obj/elf/object_file.rb
    lib/zr/obj/macho/object_file.rb
    lib/zr/prism.rb
    lib/zr/timing.rb
    lib/zr/runtime/lib/zr/eval/runtime.rb
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
