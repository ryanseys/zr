# frozen_string_literal: true

require "test_helper"
require "rbs"

# Each kernel def's `#:` comment is inline RBS. RBS reads the kernel's
# files with sig/zr/kern.rbs, which declares the type names, and gives
# each def the type that the lowering compiles it with.
class KernRbsTest < Minitest::Test
  TARGETS = %w[aarch64-apple-darwin aarch64-linux-musl wasm32-wasi].freeze
  NAMES = Zr::Machine::RBS_TYPES.to_h do |name, type|
    [type, %w[bool void].include?(name) ? name : "::Zr::Kern::#{name}"]
  end.freeze

  TARGETS.each do |triple|
    define_method("test_rbs_reads_each_def_type_on_#{triple.tr("-", "_")}") do
      files = Zr::RuntimeSources.for(Zr::Target.fetch(triple)).kernel_files
      env = RBS::Environment.from_loader(RBS::EnvironmentLoader.new)
      add_rbs(env, File.join(ROOT, "sig/zr/kern.rbs"))
      files.each { |path| add_ruby(env, path) }
      kern = RBS::DefinitionBuilder.new(env: env.resolve_type_names).build_instance(RBS::TypeName.parse("::Zr::Kern"))

      unit = Zr::Machine::Lower.new(files.map { |path| [File.read(path), path] }, Zr::Machine::Symbols.new).tap(&:run)
      unit.declared_defs.each_value do |d|
        want = "(#{d.params.map { |_, type| NAMES.fetch(type) }.join(", ")}) -> #{NAMES.fetch(d.ret)}"
        method = kern.methods[d.name.to_sym]

        assert method, "#{triple}: RBS has no type for #{d.name}"
        assert_equal [want], method.method_types.map(&:to_s), d.name
      end
    end
  end

  private

  def add_rbs(env, path)
    buffer = RBS::Buffer.new(name: Pathname(path), content: File.read(path))
    _, directives, decls = RBS::Parser.parse_signature(buffer)
    env.add_source(RBS::Source::RBS.new(buffer, directives, decls))
  end

  def add_ruby(env, path)
    text = File.read(path)
    buffer = RBS::Buffer.new(name: Pathname(path), content: text)
    prism = Prism.parse(text)
    result = RBS::InlineParser.parse(buffer, prism)

    assert_empty result.diagnostics.map(&:message), path
    env.add_source(RBS::Source::Ruby.new(buffer, prism, result.declarations, result.diagnostics))
  end
end
