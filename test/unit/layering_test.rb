# frozen_string_literal: true

require "test_helper"

# The compiler's layers are the first directory under `lib/zr` (hir, ir,
# lower, machine, backend, obj, native, eval, libraries, prism_backend),
# or "top" for a file directly under `lib/zr`. `top` holds both the leaf
# utilities (`Zr::Refused`, `Zr::Bytes`, `Zr::Target`,
# `Zr::Paths`, ...) that every layer may use, and each subsystem's own
# aggregator file (`hir.rb`, `ir.rb`, `lower.rb`, `eval.rb`, ...), which
# may in turn use any layer to assemble it.
#
# This walks every `require_relative` under `lib/zr` and checks that a
# file requiring into another layer does so only where ALLOWED says the
# dependency runs downward: the back end does not reach into the front
# end, and a base format does not reach into what reads it. KNOWN lists
# today's exceptions to that, each with the file that makes it and the
# reason a later refactor removes it; a KNOWN entry that no longer has a
# matching edge fails too, so the list shrinks as each is fixed instead
# of quietly going stale.
class LayeringTest < Minitest::Test
  LIB = Pathname.new(File.join(ROOT, "lib/zr")).freeze

  ALLOWED = {
    "top" => %w[top hir ir lower machine backend obj native eval libraries prism_backend],
    "hir" => %w[top],
    "ir" => %w[top],
    # `Lower` reads HIR and emits IR. `machine/description` is the one
    # machine-dialect file it uses, and it is data only (a struct
    # layout), not code that runs a backend or writes an object.
    "lower" => %w[top hir ir machine],
    "machine" => %w[top obj],
    "backend" => %w[top ir obj],
    "obj" => %w[top],
    "native" => %w[top ir obj backend machine],
    "eval" => %w[top],
    "libraries" => %w[top],
    "prism_backend" => %w[top],
  }.freeze

  # `[from layer, to layer] => the files whose edge this excuses`. A
  # later refactor removes these; each reaches directly into
  # `backend/aarch64` for a detail (relocations, the frame stub) that
  # belongs to the object writer or the machine dialect instead.
  KNOWN = {
    %w[obj backend] => %w[obj/jit.rb obj/macho/block.rb],
    %w[machine backend] => %w[machine/lower.rb],
  }.freeze

  def test_every_cross_layer_edge_is_allowed_or_known
    violations = edges.reject { |from, to, file| allowed?(from, to) || known?(from, to, file) }

    assert_empty violations.map { |from, to, file| "#{file}: #{from} -> #{to} (not in ALLOWED or KNOWN)" }
  end

  def test_every_known_violation_still_has_a_matching_edge
    seen = edges.each_with_object(Hash.new { |h, k| h[k] = [] }) { |(from, to, file), h| h[[from, to]] << file }

    KNOWN.each do |edge, files|
      missing = files - seen.fetch(edge, [])

      assert_empty missing, "#{edge.join(" -> ")}: shrink KNOWN, it no longer needs #{missing.join(", ")}"
    end
  end

  private

  def allowed?(from, to) = from == to || ALLOWED.fetch(from).include?(to)

  def known?(from, to, file) = KNOWN.fetch([from, to], []).include?(file)

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
