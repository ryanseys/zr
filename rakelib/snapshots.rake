# frozen_string_literal: true

# Four generated files that the unit tests check. Each `rake test:unit`
# generates them again and compares them with the committed files. Thus
# an out-of-date file causes a test failure.
#
#   rake gen:description             runtime/ext/os/<os>/zr_description.rb
#   rake 'gen:description[wasm32-wasi]'
#   rake gen:libsystem               lib/zr/obj/macho/libsystem.rb
#   rake gen:prism_generate          runtime/ext/prism/ruby/*.rb
#   rake gen:prism_encoding_tables   runtime/ext/prism/ruby/encoding_tables.rb
#
# The generators are in `test/support/generators/`. These tasks run the
# same scripts in the same way as the tests. `test/unit/description_test.rb`,
# `libsystem_test.rb` and `prism_test.rb` fail when a file is out of date.
# `ZR_BLESS=1 rake test:unit N=/Description/` also writes the first two
# files again.

module Snapshots
  ORACLE = File.expand_path("../test/support/generators", __dir__)

  module_function

  # Runs one generator with this checkout's ruby and the compiler on the
  # load path, as the tests run it.
  def run(name, *argv)
    argv = [Gem.ruby, "-I#{File.join(ROOT, "lib")}", File.join(ORACLE, "#{name}.rb"), *argv]
    out = IO.popen(argv, &:read)
    abort("rake gen:#{name}: #{File.join("test/support/generators", "#{name}.rb")} failed") unless $?.success?
    out
  end
end

namespace :gen do
  desc "Write runtime/ext/os/<os>/zr_description.rb: rake 'gen:description[wasm32-wasi]'"
  task(:description, [:triple]) do |_, args|
    require_relative "../lib/zr/runtime"
    target = args[:triple] ? (Zr::Target.fetch(args[:triple]) || abort("no target #{args[:triple]}")) : Zr::Target.default
    zr_write("runtime/ext/os/#{target.os_layer}/zr_description.rb") { |io| io.print Snapshots.run("description", target.triple) }
  end

  desc "Write lib/zr/obj/macho/libsystem.rb"
  task(:libsystem) do
    zr_write("lib/zr/obj/macho/libsystem.rb") { |io| io.print Snapshots.run("libsystem") }
  end

  desc "Write runtime/ext/prism/ruby/*.rb: rake 'gen:prism_generate[--check]'"
  task(:prism_generate, [:opts]) { |_, args| puts Snapshots.run("prism_generate", *args[:opts].to_s.split) }

  desc "Write runtime/ext/prism/ruby/encoding_tables.rb: rake 'gen:prism_encoding_tables[--check]'"
  task(:prism_encoding_tables, [:opts]) { |_, args| puts Snapshots.run("prism_encoding_tables", *args[:opts].to_s.split) }
end
