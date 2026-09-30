# frozen_string_literal: true

require "test_helper"

# The compiler's layers are the first directory under `lib/zr` (hir, ir,
# lower, machine, backend, obj, native, eval, libraries, prism_shim,
# bootstrap, cache),
# or "top" for a file directly under `lib/zr`. `top` holds both the leaf
# utilities (`Zr::Refused`, `Zr::Bytes`, `Zr::Target`,
# `Zr::Paths`, ...) that every layer may use, and each subsystem's own
# aggregator file (`hir.rb`, `ir.rb`, `lower.rb`, `eval.rb`, ...), which
# may in turn use any layer to assemble it.
#
# This walks every `require_relative` under `lib/zr` and checks that a
# file requiring into another layer does so only where ALLOWED says the
# dependency runs downward: the back end does not reach into the front
# end, and a base format does not reach into what reads it. There are no
# exceptions.
class LayeringTest < Minitest::Test
  LIB = Pathname.new(File.join(ROOT, "lib/zr")).freeze

  ALLOWED = {
    "top" => %w[top hir ir lower machine backend obj native eval libraries prism_shim bootstrap cache],
    "hir" => %w[top],
    "ir" => %w[top],
    # `Lower` reads HIR and emits IR. `machine/description` is the one
    # machine-dialect file it uses, and it is data only (a struct
    # layout), not code that runs a backend or writes an object.
    "lower" => %w[top hir ir machine],
    "machine" => %w[top obj],
    "backend" => %w[top ir obj],
    "obj" => %w[top],
    "native" => %w[top ir obj backend machine cache],
    "eval" => %w[top],
    "libraries" => %w[top],
    "prism_shim" => %w[top],
    # The compiler that zr compiled (lib/zr/bootstrap/handoff.rb): a driver of the
    # CLI, which no layer of a build uses.
    "bootstrap" => %w[top],
    # The caches between builds (lib/zr/cache/store.rb). A lowering entry
    # holds IR and the code cache's machine code; the janitor also removes
    # the compiled compilers of other versions.
    "cache" => %w[top ir native bootstrap],
  }.freeze

  def test_every_cross_layer_edge_is_allowed
    violations = edges.reject { |from, to, _| allowed?(from, to) }

    assert_empty violations.map { |from, to, file| "#{file}: #{from} -> #{to} (not in ALLOWED)" }
  end

  private

  def allowed?(from, to) = from == to || ALLOWED.fetch(from).include?(to)

  # `[from layer, to layer, file]`, relative to `LIB`, for every
  # `require_relative` that reaches into another layer. A require that
  # leaves `lib/zr` entirely (the vendored prism extension) is not part
  # of this layering, and is left out.
  def edges
    files.flat_map do |file|
      from = layer_of(file)
      dir = file.dirname
      requires(file).filter_map do |name|
        target = Pathname.new("#{(dir + name).cleanpath}.rb")
        next unless target.exist? && target.to_s.start_with?("#{LIB}/")

        to = layer_of(target)
        [from, to, file.relative_path_from(LIB).to_s] if to != from
      end
    end
  end

  def requires(file) = file.readlines.filter_map { |line| line[/require_relative\s+["']([^"']+)["']/, 1] }

  def layer_of(path)
    parts = path.relative_path_from(LIB).to_s.split("/")
    parts.one? ? "top" : parts.first
  end

  def files = LIB.glob("**/*.rb").sort
end
