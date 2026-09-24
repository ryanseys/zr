# frozen_string_literal: true

require "spec_helper"

describe "YAML: loading files" do
  it "object to yaml" do
    result = zr(<<~'RUBY')
      require "yaml"

      p({ "x" => 1 }.to_yaml)
      p [1, 2].to_yaml
      p "s".to_yaml
    RUBY

    _(result).must_answer <<~'OUT'
      "---\nx: 1\n"
      "---\n- 1\n- 2\n"
      "--- s\n"
    OUT
  end

  it "psych load file and stream" do
    result = zr(<<~'RUBY')
      require "yaml"

      # load_stream returns every document in a multi-document string.
      stream = <<~YAML
        ---
        name: alice
        role: admin
        ---
        name: bob
        role: user
      YAML
      p Psych.load_stream(stream)

      # The block form yields each document in turn.
      names = []
      Psych.load_stream(stream) { |doc| names << doc["name"] }
      p names

      # load_file reads and parses a file's first document.
      path = "/tmp/sp_psych_example.yaml"
      File.write(path, "fruits:\n  - apple\n  - banana\ncount: 2\n")
      p Psych.load_file(path)
      File.delete(path)
    RUBY

    _(result).must_answer <<~'OUT'
      [{"name" => "alice", "role" => "admin"}, {"name" => "bob", "role" => "user"}]
      ["alice", "bob"]
      {"fruits" => ["apple", "banana"], "count" => 2}
    OUT
  end

  it "psych node tree emits yaml" do
    result = zr(<<~'RUBY')
      require "psych"

      stream = Psych::Nodes::Stream.new
      stream.children << Psych.parse("a: 1\n")
      puts stream.yaml
    RUBY

    _(result).must_answer "a: 1\n"
  end

  it "psych scalar node knows where it ends" do
    result = zr(<<~'RUBY')
      require "psych"

      doc = Psych.parse("a: hello\nb: 2\n")
      key = doc.root.children[0]
      puts "scalar start #{key.start_line}:#{key.start_column}"
      puts "scalar end   #{key.end_line}:#{key.end_column}"
      puts "mapping start #{doc.root.start_line}:#{doc.root.start_column}"
      puts "mapping end   #{doc.root.end_line}:#{doc.root.end_column}"
    RUBY

    _(result).must_answer <<~'OUT'
      scalar start 0:0
      scalar end   0:1
      mapping start 0:0
      mapping end   2:0
    OUT
  end

  it "YAML's octal is 017, so the ruby spelling 0o17 loads as a String" do
    result = zr(<<~'RUBY')
      # YAML's octal scalar is `017`; the Ruby-spelling `0o17` is a plain
      # STRING to psych. zr parses it as octal 15. (Found by the 2026-08-24
      # probe sweep.)
      require "yaml"
      p YAML.safe_load("w: 0o17")
      p YAML.safe_load("v: 017")
    RUBY

    _(result).must_answer <<~'OUT'
      {"w" => "0o17"}
      {"v" => 15}
    OUT
  end

  it "require \"yaml\" exposes YAML and Psych, and both load and dump what ruby does" do
    result = zr(<<~'RUBY')
      # `require "yaml"` exposes both `YAML` and `Psych` (Ruby's `yaml.rb` is
      # `YAML = Psych`); dump uses Psych's block style (sequences under a key
      # stay at the key's indent).

      require "yaml"
      print YAML.dump({"a" => 1, "b" => [2, "x"]})
      puts YAML.load("list:\n- a\n- b").inspect
      puts Psych.load("x: 1").inspect
    RUBY

    _(result).must_answer <<~'OUT'
      ---
      a: 1
      b:
      - 2
      - x
      {"list" => ["a", "b"]}
      {"x" => 1}
    OUT
  end

  it "safe_load raises for an alias or a class its options do not name" do
    result = zr(<<~'RUBY')
      # The cycle this program builds on purpose, and the census it leaves
      # behind. A cycle alive at exit is not a defect: it is a ring the
      # program never broke, so the census below is recorded as an
      # observation rather than gated on.
      #
      # The last row loads a mapping whose `*x` alias resolves to the mapping itself, which is why it prints `{...}`.
      # At exit: cycle leak: 1 objects (Hash x1)
      # `YAML.safe_load`'s option machinery: an alias without `aliases: true`
      # raises Psych::AliasesNotEnabled (zr silently resolves `*x` to nil --
      # data loss -- and ignores the option, so even `aliases: true` answers
      # nil); a Symbol without `permitted_classes: [Symbol]` raises
      # Psych::DisallowedClass (zr loads it); and `permitted_classes: [Date]`
      # loads a date scalar as Date (zr raises NameError). (Found by the
      # 2026-08-24 probe sweep.)
      require "yaml"
      begin
        p YAML.safe_load("a: &x [1]\nb: *x")
      rescue Psych::AliasesNotEnabled => e
        puts e.class
      end
      p YAML.safe_load("a: &x [1]\nb: *x", aliases: true)
      begin
        p YAML.safe_load(":sym: 1")
      rescue Psych::DisallowedClass => e
        puts "#{e.class}: #{e.message}"
      end
      p YAML.safe_load("d: 2001-02-03", permitted_classes: [Date])
      # A re-bound anchor resolves to its LATEST value, and a self-referential
      # alias answers the recursive structure ({...}), not nil.
      p YAML.safe_load("a: &x 1\nb: &x 2\nc: *x", aliases: true)
      p YAML.safe_load("a: &x\n  b: *x", aliases: true)
    RUBY

    _(result).must_answer <<~'OUT'
      Psych::AliasesNotEnabled
      {"a" => [1], "b" => [1]}
      Psych::DisallowedClass: Tried to load unspecified class: Symbol
      {"d" => #<Date: 2001-02-03 ((2451944j,0s,0n),+0s,-Infj)>}
      {"a" => 1, "b" => 2, "c" => 2}
      {"a" => {"b" => {...}}}
    OUT
  end

  it "a plain scalar resolves by YAML 1.1 rules, so yes is a boolean and 017 is octal" do
    result = zr(<<~'RUBY')
      # Psych resolves plain scalars by YAML 1.1 rules: yes/no/on/off (any
      # case) are booleans, Null/NULL are nil, 017 is OCTAL 15, 1:02:03 is the
      # sexagesimal 3723, and "1.0e3"/"1E2" stay STRINGS (the 1.1 float form
      # needs a digit after the point). A resolver that applies 1.2 rules to all
      # of these has the Norway problem in both directions.
      # (Found by the 2026-08-24 probe sweep.)
      require "yaml"
      p YAML.safe_load("[y, Y, yes, Yes, YES, n, no, No, NO, on, On, off, true, false]")
      p YAML.safe_load("[~, null, Null, NULL, '']")
      p YAML.safe_load("[017, 0x1A, 1_000, +5]")
      p YAML.safe_load("t: 1:02:03")
      p YAML.safe_load("[1.0e3, .5, 5., 1E2]")
      p YAML.safe_load("no: 1\nyes: 2").keys
    RUBY

    _(result).must_answer <<~'OUT'
      ["y", "Y", true, true, true, "n", false, false, false, true, true, false, true, false]
      [nil, nil, nil, nil, ""]
      [15, 26, 1000, 5]
      {"t" => 3723}
      ["1.0e3", 0.5, 5.0, "1E2"]
      [false, true]
    OUT
  end
end
