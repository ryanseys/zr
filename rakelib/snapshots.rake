# frozen_string_literal: true

# Four generated files that a check holds rather than a task: each is
# written again on every `rake test:unit` and compared with what is
# committed, so a stale one is a failing test rather than something you
# have to remember to run.
#
#   rake gen:description             rt/ext/os/<os>/zr_description.rb
#   rake 'gen:description[wasm32-wasi]'
#   rake gen:libsystem               lib/zr/obj/macho/libsystem.rb
#   rake gen:prism_generate          rt/ext/prism/ruby/*.rb
#   rake gen:prism_encoding_tables   rt/ext/prism/ruby/encoding_tables.rb
#
# The generators live in `test/support/oracle/`, beside the tests that
# run them, and the tasks here run the same scripts the same way:
# `test/unit/description_test.rb`, `libsystem_test.rb` and
# `prism_test.rb` are the ones that fail when a file has gone stale, and
# `ZR_BLESS=1 rake test:unit N=/Description/` is the other way to write
# the first two again.

module Snapshots
  ORACLE = File.expand_path("../test/support/oracle", __dir__)

  module_function

  # One oracle, run under the checkout's own ruby with the compiler on
  # the load path, as the tests run it.
  def run(name, *argv)
    argv = [Gem.ruby, "-I#{File.join(ROOT, "lib")}", File.join(ORACLE, "#{name}.rb"), *argv]
    out = IO.popen(argv, &:read)
    abort("rake gen:#{name}: #{File.join("test/support/oracle", "#{name}.rb")} failed") unless $?.success?
    out
  end
end

namespace :gen do
  desc "Write rt/ext/os/<os>/zr_description.rb: rake 'gen:description[wasm32-wasi]'"
  task(:description, [:triple]) do |_, args|
    require_relative "../lib/zr/zr"
    target = args[:triple] ? (Zr::Target.fetch(args[:triple]) || abort("no target #{args[:triple]}")) : Zr::Target.default
    zr_write("rt/ext/os/#{target.os_layer}/zr_description.rb") { |io| io.print Snapshots.run("description", target.triple) }
  end

  desc "Write lib/zr/obj/macho/libsystem.rb"
  task(:libsystem) do
    zr_write("lib/zr/obj/macho/libsystem.rb") { |io| io.print Snapshots.run("libsystem") }
  end

  desc "Write rt/ext/prism/ruby/*.rb: rake 'gen:prism_generate[--check]'"
  task(:prism_generate, [:opts]) { |_, args| puts Snapshots.run("prism_generate", *args[:opts].to_s.split) }

  desc "Write rt/ext/prism/ruby/encoding_tables.rb: rake 'gen:prism_encoding_tables[--check]'"
  task(:prism_encoding_tables, [:opts]) { |_, args| puts Snapshots.run("prism_encoding_tables", *args[:opts].to_s.split) }
end
