# frozen_string_literal: true

require "spec_helper"

describe "YAML programs" do
  it "binary string survives a yaml round trip" do
    result = ze0(<<~'RUBY')
      # A BINARY string is not valid UTF-8, so YAML carries it as a `!!binary`
      # base64 scalar and loads it back byte-for-byte. zeo's round trip answers a
      # string that no longer equals the one it dumped.
      #
      # Carved out of tests/probe_roundtrip.rb ("yaml:string_binary").
      require "yaml"

      s = "\xff\xfe".b
      back = YAML.unsafe_load(YAML.dump(s))
      puts back == s
      puts back.encoding
      puts back.bytes.inspect
    RUBY

    _(result).must_answer <<~'OUT'
      true
      ASCII-8BIT
      [255, 254]
    OUT
  end

  it "nested collection as a mapping value ends its turn" do
    _(ze0(<<~'RUBY')).must_answer "---\na:\n- 1\n-\n- true\nb:\n  c: 1\n  e:\n    f:\n    - 2\nd: x\n---\n- a:\n    b:\n    - 1\n  g: 3\n- 2\n---\n? - 1\n  - 2\n: x: 1\n\"y\": []\n{\"a\" => [1], \"b\" => {\"c\" => 1}}\n---\n? a: 1\n  b: 2\n: - 3\n  - z: 1\n? - - 1\n: 1\nk:\n  ? - 1\n  : ? - 2\n    : 3\n---\n- - - 1\n    - 2\n- a:\n    b:\n    - - 1\n---\np: &1\n- 1\nq: *1\nr:\n  s: *1\n"
      # A collection that is the value of a mapping key takes that key's turn, so the
      # next node is a key again; a collection as a key shares its `?` line.

      require "yaml"
      puts({"a"=>[1,nil,true],"b"=>{"c"=>1, "e" => {"f" => [2]}}, "d" => "x"}.to_yaml)
      puts [{"a"=>{"b"=>[1]}, "g" => 3}, 2].to_yaml
      puts({[1, 2] => {"x" => 1}, "y" => []}.to_yaml)
      p YAML.load({"a"=>[1],"b"=>{"c"=>1}}.to_yaml)
      puts({{"a"=>1, "b"=>2} => [3, {"z"=>1}], [[1]] => 1, "k" => {[1] => {[2] => 3}}}.to_yaml)
      puts [[[1, 2]], {"a" => {"b" => [[1]]}}].to_yaml
      a = [1]
      puts({"p" => a, "q" => a, "r" => {"s" => a}}.to_yaml)

    RUBY
  end

  it "psych parse node tree" do
    result = ze0(<<~'RUBY')
      # `Psych.parse` and the `Psych::Nodes::*` tree it answers.
      #
      # The tree is the DOCUMENT rather than the data: a gem walks it to read a tag,
      # rewrite a scalar or count anchors, and `to_ruby` turns any node -- parsed or
      # hand-built -- into the value it describes.

      require "psych"

      def show(label, v)
        puts "#{label}\t#{v.inspect}"
      end

      # --- the shape of a parsed document --------------------------------------
      doc = Psych.parse("--- \na: 1\nb: [2, 3]\n")
      show "document class", doc.class
      show "document children", doc.children.size
      show "implicit", doc.implicit
      show "version", doc.version
      show "tag directives", doc.tag_directives

      root = doc.root
      show "root class", root.class
      show "root style block", root.style == Psych::Nodes::Mapping::BLOCK
      show "root children", root.children.size

      key = root.children[0]
      show "key class", key.class
      show "key value", key.value
      show "key plain", key.plain
      show "key quoted", key.quoted
      show "key style plain", key.style == Psych::Nodes::Scalar::PLAIN

      seq = root.children[3]
      show "seq class", seq.class
      show "seq style flow", seq.style == Psych::Nodes::Sequence::FLOW
      show "seq children", seq.children.map(&:value)

      # --- quoting and block scalars keep their style ---------------------------
      styles = Psych.parse("- plain\n- 'single'\n- \"double\"\n- |\n  literal\n- >\n  folded\n")
      show "styles", styles.root.children.map(&:style)
      show "quoted flags", styles.root.children.map(&:quoted)

      # --- anchors come back as NAMES, not numbers ------------------------------
      anchored = Psych.parse("a: &base {x: 1}\nb: *base\n")
      pairs = anchored.root.children
      show "anchor name", pairs[1].anchor
      show "alias class", pairs[3].class
      show "alias anchor", pairs[3].anchor

      # --- tags survive ---------------------------------------------------------
      tagged = Psych.parse("--- !!str 42\n")
      show "scalar tag", tagged.root.tag
      show "scalar value", tagged.root.value

      taggedmap = Psych.parse("--- !ruby/object:Widget\nname: bolt\n")
      show "mapping tag", taggedmap.root.tag

      # --- an explicit document says so ----------------------------------------
      show "explicit implicit?", Psych.parse("--- \na: 1\n").implicit
      show "bare implicit?", Psych.parse("a: 1\n").implicit

      # --- directives -----------------------------------------------------------
      withdirs = Psych.parse("%YAML 1.1\n%TAG !e! tag:example.com,2000:\n---\na: 1\n")
      show "version", withdirs.version
      show "tag directives", withdirs.tag_directives

      # --- the whole stream -----------------------------------------------------
      stream = Psych.parse_stream("--- 1\n--- 2\n")
      show "stream class", stream.class
      show "stream documents", stream.children.size
      show "stream roots", stream.children.map { |d| d.root.value }

      collected = []
      Psych.parse_stream("--- 1\n--- 2\n") { |d| collected << d.root.value }
      show "yielded", collected

      # --- an empty stream ------------------------------------------------------
      show "empty parse", Psych.parse("")

      # --- each walks depth first, self first -----------------------------------
      show "each classes", Psych.parse("a: [1]\n").each.map { |n| n.class.to_s.split("::").last }

      # --- to_ruby on a parsed tree --------------------------------------------
      show "document to_ruby", Psych.parse("a: 1\nb: [2, 3]\n").to_ruby
      show "root to_ruby", Psych.parse("a: 1\n").root.to_ruby
      show "scalar to_ruby", Psych.parse("--- 42\n").root.to_ruby
      show "stream to_ruby", Psych.parse_stream("--- 7\n").to_ruby

      # --- to_ruby on a tree built by hand -------------------------------------
      built = Psych::Nodes::Mapping.new
      built.children << Psych::Nodes::Scalar.new("k")
      built.children << Psych::Nodes::Scalar.new("9")
      show "hand-built to_ruby", built.to_ruby

      wrapped = Psych::Nodes::Document.new
      wrapped.children << built
      show "hand-built document", wrapped.to_ruby

      # --- an alias in a hand-built tree resolves ------------------------------
      aliased = Psych::Nodes::Mapping.new
      aliased.children << Psych::Nodes::Scalar.new("a")
      aliased.children << Psych::Nodes::Sequence.new("keep")
      aliased.children << Psych::Nodes::Scalar.new("b")
      aliased.children << Psych::Nodes::Alias.new("keep")
      built_alias = aliased.to_ruby
      show "alias resolved", built_alias["a"].equal?(built_alias["b"])

      # `Nodes::Node#yaml` is deliberately absent from these rows: zeo refuses it
      # (see tests/gaps/a_psych_node_tree_emits_yaml.rb) and ruby raises a
      # different error again for a bare Document, so the row would compare two
      # unrelated refusals rather than one behaviour.
    RUBY

    _(result).must_answer <<~'OUT'
      document class	Psych::Nodes::Document
      document children	1
      implicit	false
      version	[]
      tag directives	[]
      root class	Psych::Nodes::Mapping
      root style block	true
      root children	4
      key class	Psych::Nodes::Scalar
      key value	"a"
      key plain	true
      key quoted	false
      key style plain	true
      seq class	Psych::Nodes::Sequence
      seq style flow	true
      seq children	["2", "3"]
      styles	[1, 2, 3, 4, 5]
      quoted flags	[false, true, true, true, true]
      anchor name	"base"
      alias class	Psych::Nodes::Alias
      alias anchor	"base"
      scalar tag	"tag:yaml.org,2002:str"
      scalar value	"42"
      mapping tag	"!ruby/object:Widget"
      explicit implicit?	false
      bare implicit?	true
      version	[1, 1]
      tag directives	[["!e!", "tag:example.com,2000:"]]
      stream class	Psych::Nodes::Stream
      stream documents	2
      stream roots	["1", "2"]
      yielded	["1", "2"]
      empty parse	false
      each classes	["Scalar", "Scalar", "Sequence", "Mapping", "Document"]
      document to_ruby	{"a" => 1, "b" => [2, 3]}
      root to_ruby	{"a" => 1}
      scalar to_ruby	42
      stream to_ruby	[7]
      hand-built to_ruby	{"k" => 9}
      hand-built document	{"k" => 9}
      alias resolved	true
    OUT
  end

  it "psych syntax error carries marks" do
    result = ze0(<<~'RUBY')
      require "yaml"
      begin
        YAML.safe_load("ok: 1\nbad: [")
      rescue Psych::SyntaxError => e
        p [e.line, e.column, e.file]
        puts e.message
      end

      begin
        YAML.parse("x: [", filename: "f.yml")
      rescue Psych::SyntaxError => e
        p [e.file, e.line, e.column]
      end

      begin
        YAML.load("- a\n- \"b\n")
      rescue Psych::SyntaxError => e
        p [e.line, e.column, e.problem]
      end

      begin
        YAML.load("a: *nope\n")
      rescue => e
        p [e.class.to_s, e.message]
      end

      p Psych::SyntaxError.instance_methods(false).sort
    RUBY

    _(result).must_answer <<~'OUT'
      [3, 1, nil]
      (<unknown>): did not find expected node content while parsing a flow node at line 3 column 1
      ["f.yml", 2, 1]
      [2, 3, "found unexpected end of stream"]
      ["Psych::AliasesNotEnabled", "Alias parsing was not enabled. To enable it, pass `aliases: true` to `Psych::load` or `Psych::safe_load`."]
      [:column, :context, :file, :line, :offset, :problem]
    OUT
  end

  it "psych version constant" do
    result = ze0(<<~'RUBY')
      require "yaml"

      p Psych::VERSION.class
      p Psych.const_defined?(:VERSION)
    RUBY

    _(result).must_answer <<~'OUT'
      String
      true
    OUT
  end

  it "yaml core tags" do
    result = ze0(<<~'RUBY')
      # Psych applies core and ruby tags: `!!str` forces string, `!!int`/
      # `!!float` coerce a quoted scalar, `!!binary` base64-decodes, `!!set`
      # is gated (Psych::Set needs permitting), `!!omap` loads as a Hash,
      # `!ruby/symbol` is gated behind `permitted_classes: [Symbol]` (and
      # converts when permitted, incl. under unsafe_load), and `!ruby/object:`
      # is gated. zeo ignores the tags wholesale. (Found by the 2026-08-24
      # probe sweep.)
      require "yaml"
      def show
        p yield
      rescue Psych::DisallowedClass => e
        puts "#{e.class}: #{e.message}"
      end
      show { YAML.safe_load("v: !!str 123") }
      show { YAML.safe_load(%(v: !!int "42")) }
      show { YAML.safe_load("v: !!float 3") }
      show { YAML.safe_load("v: !!binary aGVsbG8=") }
      show { YAML.safe_load("v: !!set {a: null, b: null}") }
      show { YAML.safe_load("v: !!omap [{a: 1}, {b: 2}]") }
      show { YAML.safe_load("v: !ruby/symbol foo") }
      show { YAML.safe_load("v: !ruby/symbol foo", permitted_classes: [Symbol]) }
      show { YAML.safe_load("v: !ruby/object:OpenStruct {}") }
      show { Psych.unsafe_load("v: !ruby/symbol s") }
    RUBY

    _(result).must_answer <<~'OUT'
      {"v" => "123"}
      {"v" => 42}
      {"v" => 3.0}
      {"v" => "hello"}
      Psych::DisallowedClass: Tried to load unspecified class: Psych::Set
      {"v" => {"a" => 1, "b" => 2}}
      Psych::DisallowedClass: Tried to load unspecified class: Symbol
      {"v" => :foo}
      Psych::DisallowedClass: Tried to load unspecified class: OpenStruct
      {"v" => :s}
    OUT
  end

  it "yaml merge keys" do
    result = ze0(<<~'RUBY')
      # The `<<` merge key splices the referenced mapping(s) into the host
      # mapping -- single alias, alias list, and inline mapping forms. zeo
      # keeps a literal "<<" key (with the earlier alias bug feeding it nil).
      # (Found by the 2026-08-24 probe sweep.)
      require "yaml"
      p YAML.safe_load("base: &b {x: 1, y: 2}\nchild:\n  <<: *b\n  y: 9", aliases: true)
      p YAML.safe_load("a: &a {x: 1}\nb: &b {y: 2}\nc:\n  <<: [*a, *b]\n  z: 3", aliases: true)
      p YAML.safe_load("c:\n  <<: {x: 1}\n  y: 2")
    RUBY

    _(result).must_answer <<~'OUT'
      {"base" => {"x" => 1, "y" => 2}, "child" => {"x" => 1, "y" => 9}}
      {"a" => {"x" => 1}, "b" => {"y" => 2}, "c" => {"y" => 2, "x" => 1, "z" => 3}}
      {"c" => {"x" => 1, "y" => 2}}
    OUT
  end

  it "yaml symbol key roundtrip" do
    result = ze0(<<~'RUBY')
      # `YAML.dump` emits a Symbol as the plain scalar `:name`, and `YAML.load` reads
      # that spelling back as a Symbol -- so a Hash with symbol keys survives the
      # round trip. The QUOTING is what carries the distinction: a quoted `":x"` is
      # still a String, which is why the load side has to read the parser's scalar
      # style rather than just the text.
      require "yaml"

      dumped = YAML.dump({x: "hi", y: 2})
      puts dumped
      p YAML.load(dumped)

      [":x", ":X", ":a-b", ":1", ":@iv", ":+", ":x y", "::a"].each { |s| p [s, YAML.load(s)] }

      p YAML.dump(:"with space")
      p YAML.load(YAML.dump(:"with space"))

      # Quoted, and block, scalars stay Strings.
      p YAML.load("- :a\n- \":b\"\n- ':c'\n")
      p YAML.load(":a: 1\n\":b\": 2\n")
      p YAML.load("--- |\n  :not a symbol\n")
      p YAML.load("--- >\n  :also not\n")

      # Nesting, in both key and value position.
      p YAML.load(YAML.dump({a: {b: [:c, "d"]}}))
      p YAML.load("? - :k\n: :v\n")
      p YAML.load(YAML.dump([{one: 1}, {two: :owt}]))

      # The rest of the plain-scalar scanner is unchanged.
      p YAML.load("- 1\n- ~\n- null\n- true\n- False\n- 0x1f\n- 3.5\n- .inf\n- -.inf\n- ''\n")
      ["1_000", "_1", "1_", "1__0", "-1_2", "1_000.5", "a_1"].each { |s| p [s, YAML.load(s)] }

      p YAML.load_stream("---\n:a: 1\n---\n- :b\n")
      p YAML.load("")
      p YAML.load("--- {}\n")
      p YAML.load("--- []\n")
    RUBY

    _(result).must_answer <<~'OUT'
      ---
      :x: hi
      :y: 2
      {x: "hi", y: 2}
      [":x", :x]
      [":X", :X]
      [":a-b", :"a-b"]
      [":1", :"1"]
      [":@iv", :@iv]
      [":+", :+]
      [":x y", :"x y"]
      ["::a", :":a"]
      "--- :with space\n"
      :"with space"
      [:a, ":b", ":c"]
      {a: 1, ":b" => 2}
      ":not a symbol\n"
      ":also not\n"
      {a: {b: [:c, "d"]}}
      {[:k] => :v}
      [{one: 1}, {two: :owt}]
      [1, nil, nil, true, false, 31, 3.5, Infinity, -Infinity, ""]
      ["1_000", 1000]
      ["_1", "_1"]
      ["1_", "1_"]
      ["1__0", "1__0"]
      ["-1_2", -12]
      ["1_000.5", 1000.5]
      ["a_1", "a_1"]
      [{a: 1}, [:b]]
      nil
      {}
      []
    OUT
  end
end
