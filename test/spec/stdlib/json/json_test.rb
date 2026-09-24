# frozen_string_literal: true

require "spec_helper"

describe "JSON programs" do
  it "dead loaderror rescue dropped" do
    result = zr(<<~'RUBY')
      # A `begin; require "x"; rescue LoadError; <fallback def>` guard: when the
      # require RESOLVES (a builtin/shim/file satisfied it), the rescue is DEAD --
      # CRuby's behavior when the extension IS present -- so its fallback definitions
      # never take effect. zr drops the dead rescue at compile time (the shape
      # rubygems' erb/strscan guards use).
      begin
        require "json"
      rescue LoadError
        class OnlyDefinedWhenJsonMissing
          def marker = "fallback"
        end
      end

      puts defined?(OnlyDefinedWhenJsonMissing).inspect
      puts defined?(JSON).inspect
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      "constant"
    OUT
  end

  it "gems ruby half supplies the exception class its native half raises" do
    result = zr(<<~'RUBY')
      # A gem's Ruby half can reopen its feature-gated NATIVE half and nest an
      # exception class inside it, which the native half then raises by name.
      # This is what retires the `StringScanner::Error` -> `RuntimeError`
      # divergence: a nested user exception registers under its fully qualified
      # name with a real constructor, where an ABI row cannot.

      require "json"
      require "strscan"
      begin
        JSON.parse("{oops")
      rescue JSON::ParserError => e
        p e.class.name
        p e.class.ancestors.include?(StandardError)
      end
      p JSON::ParserError.superclass.name
      p StringScanner::Error.ancestors.include?(StandardError)
    RUBY

    _(result).must_answer <<~'OUT'
      "JSON::ParserError"
      true
      "JSON::JSONError"
      true
    OUT
  end

  it "hash variant eq" do
    result = zr(<<~'RUBY')
      # Hashes compare by VALUE across storage variants, like arrays: Ruby has one
      # Hash, and a runtime-built poly hash (JSON.parse) equals the same pairs
      # written as a typed literal. Previously poly==typed-hash and mixed-variant
      # hash==hash both constant-folded to false, and .class on a boxed hash
      # printed an empty name.
      require "json"
      a = JSON.parse('{"k": 1}')
      b = { "k" => 1 }
      p a == b
      p b == a
      p a != b
      puts a.class
      p JSON.parse('{"k": "s", "n": [1, 2]}') == { "k" => "s", "n" => [1, 2] }
      p JSON.parse('{"k": 1}') == { "k" => 2 }
      p JSON.parse('{"k": 1}') == { "j" => 1 }
      p JSON.parse('{"k": 1}') == { "k" => 1, "j" => 2 }
      p JSON.parse('{"k": 1}') == [1]
      p JSON.parse('{"k": 1}') == { "k" => 1.0 }   # 1 == 1.0
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      false
      Hash
      true
      false
      false
      false
      false
      true
    OUT
  end

  it "JSON and StringIO work inside a thread" do
    result = zr(<<~'RUBY')
      require "json"
      require "stringio"

      results = []
      th = Thread.new do
        io = StringIO.new
        io.write(JSON.generate({ "a" => 1 }))
        results << io.string
      end
      th.join
      p results
    RUBY

    _(result).must_answer "[\"{\\\"a\\\":1}\"]\n"
  end

  it "issue hash to json missing" do
    result = zr(<<~'RUBY')
      # `require "json"` adds `#to_json` to the core classes, so a Hash serializes
      # through the method as well as through the explicit `JSON.generate` and
      # `JSON.dump` entry points.
      require "json"
      p({a: 1}.to_json)
    RUBY

    _(result).must_answer "\"{\\\"a\\\":1}\"\n"
  end

  it "json/add revives a class innermost first, and load turns create_additions on where parse leaves it off" do
    result = zr(<<~'RUBY')
      # `json/add/*` teaches a core class to serialize itself, and `create_additions`
      # is what reads it back: a parsed object naming a class under `JSON.create_id`
      # becomes that class's `json_create` of itself. INNERMOST FIRST, so an
      # addition receives children that are already revived. A name that resolves to
      # no constant is an ArgumentError; one whose class has no `json_create` is left
      # alone, because `json_class` is an ordinary key until some class claims it.
      #
      # `parse` leaves the option OFF and `load` turns it ON -- that difference is
      # the whole distinction between the two entry points.

      require "json"
      require "json/add/core"
      require "json/add/string"
      require "json/add/date"

      def t(label)
        r = begin
          yield.inspect
        rescue Exception => e
          "#{e.class}: #{e.message}"
        end
        puts format("%-22s %s", label, r)
      end

      R = '{"json_class":"Range","a":[1,3,false]}'

      t("parse default") { JSON.parse(R) }
      t("parse additions") { JSON.parse(R, create_additions: true) }
      t("parse off") { JSON.parse(R, create_additions: false) }
      t("load default") { JSON.load(R) }
      t("load off") { JSON.load(R, nil, create_additions: false) }
      t("symbolize+add") { JSON.parse(R, create_additions: true, symbolize_names: true) }

      t("range to_json") { (1..3).to_json }
      t("exclusive") { JSON.parse((1...3).to_json, create_additions: true) }
      t("revived class") { JSON.parse(R, create_additions: true).class }
      t("nested") do
        JSON.parse('{"json_class":"Range","a":[{"json_class":"Symbol","s":"a"},' \
                   '{"json_class":"Symbol","s":"z"},false]}', create_additions: true)
      end
      t("in array") { JSON.parse("[#{R}]", create_additions: true) }
      t("as value") { JSON.parse(%({"k":#{R}}), create_additions: true) }

      t("unknown class") { JSON.parse('{"json_class":"NoSuchThing","a":[]}', create_additions: true) }
      t("no json_create") { JSON.parse('{"json_class":"Comparable"}', create_additions: true) }

      t("symbol") { JSON.parse(:a.to_json, create_additions: true) }
      t("struct") { s = Struct.new("Pair", :x); JSON.parse(s.new(1).to_json, create_additions: true).x }
      t("exception") { JSON.parse(RuntimeError.new("boom").to_json, create_additions: true).message }
      t("time") { JSON.parse(Time.utc(2000).to_json, create_additions: true).utc.to_s }
      t("regexp") { JSON.parse(/ab/i.to_json, create_additions: true).inspect }
      t("date") { JSON.parse(Date.new(2001, 2, 3).to_json, create_additions: true).to_s }
      t("string") { JSON.parse("abc".to_json, create_additions: true) }

      t("create_id") { JSON.create_id }
      t("constants") { [defined?(JSON::Fragment), defined?(JSON::GeneratorError), defined?(JSON::GenericObject)] }
      t("JSON_LOADED") { JSON::JSON_LOADED }
      t("non-finite") { [JSON::NaN.nan?, JSON::Infinity, JSON::MinusInfinity] }
      t("fragment") { JSON.generate({ "pre" => JSON::Fragment.new("[1,2]") }) }

      # The generator's option bag carries CRuby's whole field list, and is named
      # where the C extension names it.
      t("state class") { JSON::State.name }
      t("state is aliased") { JSON::State.equal?(JSON::Ext::Generator::State) }
      t("state to_h") { JSON::State.new.to_h }
      t("state predicates") do
        s = JSON::State.new
        [s.allow_nan?, s.ascii_only?, s.script_safe?, s.escape_slash?, s.check_circular?, s.strict?]
      end
      t("no limit, no circle") { JSON::State.new(max_nesting: 0).check_circular? }
      t("state []") { JSON::State.new(indent: "  ")[:indent] }
      t("state [] unknown") { JSON::State.new[:nope] }
      t("state []= unknown") { s = JSON::State.new; s[:nope] = 1; s[:nope] }
      t("sort_keys is a proc") { JSON::State.new(sort_keys: true).sort_keys.class }
      t("sort_keys effect") { JSON.generate({ "b" => 1, "a" => 2 }, JSON::State.new(sort_keys: true)) }
      t("as_json from symbol") { JSON::State.new(as_json: :itself).as_json.class }
      t("from_state nil") { JSON::State.from_state(nil).indent }
      t("from_state hash") { JSON::State.from_state({ indent: "\t" }).indent }
      t("from_state self") { s = JSON::State.new; JSON::State.from_state(s).equal?(s) }
      t("state generate") { JSON::State.new(space: " ").generate({ "a" => 1 }) }
    RUBY

    _(result).must_answer <<~'OUT'
      parse default          {"json_class" => "Range", "a" => [1, 3, false]}
      parse additions        1..3
      parse off              {"json_class" => "Range", "a" => [1, 3, false]}
      load default           1..3
      load off               {"json_class" => "Range", "a" => [1, 3, false]}
      symbolize+add          ArgumentError: options :symbolize_names and :create_additions cannot be  used in conjunction
      range to_json          "{\"json_class\":\"Range\",\"a\":[1,3,false]}"
      exclusive              1...3
      revived class          Range
      nested                 :a..:z
      in array               [1..3]
      as value               {"k" => 1..3}
      unknown class          ArgumentError: can't get const NoSuchThing: uninitialized constant NoSuchThing
      no json_create         {"json_class" => "Comparable"}
      symbol                 :a
      struct                 1
      exception              "boom"
      time                   "2000-01-01 00:00:00 UTC"
      regexp                 "/ab/i"
      date                   "2001-02-03"
      string                 "abc"
      create_id              "json_class"
      constants              ["constant", "constant", "constant"]
      JSON_LOADED            true
      non-finite             [true, Infinity, -Infinity]
      fragment               "{\"pre\":[1,2]}"
      state class            "JSON::Ext::Generator::State"
      state is aliased       true
      state to_h             {indent: "", space: "", space_before: "", object_nl: "", array_nl: "", as_json: false, allow_nan: false, ascii_only: false, max_nesting: 100, script_safe: false, strict: false, depth: 0, buffer_initial_length: 1024, sort_keys: false}
      state predicates       [false, false, false, false, true, false]
      no limit, no circle    false
      state []               "  "
      state [] unknown       nil
      state []= unknown      1
      sort_keys is a proc    Proc
      sort_keys effect       "{\"a\":2,\"b\":1}"
      as_json from symbol    Proc
      from_state nil         ""
      from_state hash        "\t"
      from_state self        true
      state generate         "{\"a\": 1}"
    OUT
  end

  it "parse keeps an integer beyond f64 exact" do
    result = zr(<<~'RUBY')
      # `JSON.parse` keeps an integer beyond a double's precision EXACT (a
      # Bignum); a naive numeric parser converts it to Float and silently
      # loses precision -- wrong DATA, the sharpest kind. (Found by the
      # 2026-08-24 probe sweep.)
      require "json"
      p JSON.parse('{"x":123456789012345678901234567890}')["x"]
      p JSON.parse("[9007199254740993]").first
    RUBY

    _(result).must_answer "123456789012345678901234567890\n9007199254740993\n"
  end

  it "generate on a self-referential array raises JSON::NestingError" do
    result = zr(<<~'RUBY')
      # The cycle this program builds on purpose, and the census it leaves
      # behind. A cycle alive at exit is not a defect: it is a ring the
      # program never broke, so the census below is recorded as an
      # observation rather than gated on.
      #
      # `a << a` -- the circular reference the generator is supposed to name.
      # At exit: cycle leak: 1 objects (Array x1)
      # `JSON.generate` on a self-referential array raises JSON::NestingError
      # ("Did you try to serialize objects with circular references?"); the
      # serializer used to re-enter the container guard and crash the whole
      # process instead -- the third surface of the recursive-traversal guard
      # family beside `Array#join` and twin-`<=>`. (Found by the 2026-08-24
      # probe sweep.)
      require "json"
      a = [1]
      a << a
      begin
        JSON.generate(a)
      rescue JSON::NestingError => e
        puts e.class
      end
    RUBY

    _(result).must_answer "JSON::NestingError\n"
  end

  it "generate refuses NaN and Infinity unless allow_nan: says otherwise" do
    result = zr(<<~'RUBY')
      require "json"

      begin
        JSON.generate({ "a" => Float::NAN })
      rescue JSON::GeneratorError => e
        p e.class
      end
      begin
        JSON.generate({ "a" => Float::INFINITY })
      rescue JSON::GeneratorError => e
        p e.class
      end
      p JSON.generate({ "a" => Float::NAN }, allow_nan: true)
    RUBY

    _(result).must_answer <<~'OUT'
      JSON::GeneratorError
      JSON::GeneratorError
      "{\"a\":NaN}"
    OUT
  end

  it "generate refuses a string that is not valid UTF-8" do
    result = zr(<<~'RUBY')
      # JSON.generate refuses what is not valid UTF-8: an invalid-UTF-8 string
      # raises JSON::GeneratorError ("source sequence is illegal/malformed
      # utf-8"), and a binary string raises on the transcode. zr lossy-
      # replaces the first and transcodes the second -- silent data
      # corruption. The float form also differs: 1e100.to_json is "1e+100",
      # not "1.0e+100". (Found by the 2026-08-24 probe sweep.)
      require "json"
      def show
        p yield
      rescue Exception => e
        puts "#{e.class}: #{e.message}"
      end
      show { JSON.generate(["\xFF".b.force_encoding("UTF-8")]) }
      show { JSON.generate(["\xE9".b]) }
      show { 1e100.to_json }
    RUBY

    _(result).must_answer <<~'OUT'
      JSON::GeneratorError: source sequence is illegal/malformed utf-8
      JSON::GeneratorError: "\xE9" from ASCII-8BIT to UTF-8
      "1e+100"
    OUT
  end

  it "indent, space, ascii_only, script_safe and max_nesting each change what generate writes" do
    result = zr(<<~'RUBY')
      # JSON.generate's option surface is ignored wholesale: indent/object_nl/
      # array_nl/space (so pretty_generate != generate with those opts),
      # space_before, ascii_only (must \u-escape), script_safe (must escape /),
      # and the generate-side max_nesting/depth NestingError. fast_generate is
      # absent. (Found by the 2026-08-24 probe sweep.)
      require "json"
      def show
        p yield
      rescue Exception => e
        puts "#{e.class}: #{e.message}"
      end
      show { JSON.generate({ a: [1] }, indent: "  ", object_nl: "\n", array_nl: "\n", space: " ") }
      show { JSON.pretty_generate({ a: 1 }) == JSON.generate({ a: 1 }, indent: "  ", object_nl: "\n", array_nl: "\n", space: " ") }
      show { JSON.fast_generate({ a: 1 }) }
      show { JSON.generate({ a: 1 }, space_before: "_") }
      show { JSON.generate({ "k" => "é" }, ascii_only: true) }
      show { JSON.generate("</script>", script_safe: true) }
      show { JSON.generate([[[1]]], max_nesting: 2) }
    RUBY

    _(result).must_answer <<~'OUT'
      "{\n  \"a\": [\n    1\n  ]\n}"
      true
      "{\"a\":1}"
      "{\"a\"_:1}"
      "{\"k\":\"\\u00e9\"}"
      "\"<\\/script>\""
      JSON::NestingError: nesting of 2 is too deep. Did you try to serialize objects with circular references?
    OUT
  end

  it "dump takes a depth limit and an IO, and load takes nil, a proc and allow_nan:" do
    result = zr(<<~'RUBY')
      # JSON.dump/load surface: dump with a LIMIT raises ArgumentError beyond
      # it; dump to an IO WRITES to it (zr returns "" and writes nothing --
      # silent data loss); load(nil) answers nil; load's proc argument visits
      # every parsed object; JSON.parse! exists (NaN/Infinity allowed); and
      # `allow_nan: true` admits the literals to parse. (Found by the
      # 2026-08-24 probe sweep.)
      require "json"
      require "stringio"
      def show
        p yield
      rescue Exception => e
        puts "#{e.class}: #{e.message}"
      end
      show { JSON.dump([[[1]]], 2) }
      show { io = StringIO.new(+""); JSON.dump({ a: 1 }, io); io.string }
      show { JSON.load(nil) }
      show do
        seen = []
        JSON.load('{"a":[1]}', ->(o) { seen << o.class })
        seen.map(&:to_s).sort
      end
      show { JSON.parse!("[NaN, Infinity]").map { |f| f.nan? || f.infinite? } }
      show { JSON.parse("[NaN]", allow_nan: true).first.nan? }
    RUBY

    _(result).must_answer <<~'OUT'
      ArgumentError: exceed depth limit
      "{\"a\":1}"
      nil
      ["Array", "Hash", "Integer", "String"]
      [true, 1]
      true
    OUT
  end

  it "input nested too deep raises JSON::NestingError, and max_nesting: bounds the parse" do
    result = zr(<<~'RUBY')
      # JSON's depth control: too-deep input raises JSON::NestingError (a
      # distinct class rescue code depends on), and `max_nesting:` bounds the
      # parse. (Found by the 2026-08-24 probe sweep.)
      require "json"
      begin
        JSON.parse("[" * 200 + "]" * 200)
      rescue JSON::NestingError => e
        puts "#{e.class}: #{e.message}"
      end
      begin
        p JSON.parse("[[[1]]]", max_nesting: 2)
      rescue JSON::NestingError => e
        puts "#{e.class}: #{e.message}"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      JSON::NestingError: nesting of 101 is too deep
      JSON::NestingError: nesting of 3 is too deep
    OUT
  end

  it "generate, parse and pretty_generate answer what ruby's json answers" do
    result = zr(<<~'RUBY')
      require "json"
      puts JSON.generate({"a" => 1, "b" => [2, 3.5, nil, true]})
      puts JSON.parse('{"x":[1,2,3]}').inspect
      puts JSON.pretty_generate({"k" => [1, 2]})
    RUBY

    _(result).must_answer <<~'OUT'
      {"a":1,"b":[2,3.5,null,true]}
      {"x" => [1, 2, 3]}
      {
        "k": [
          1,
          2
        ]
      }
    OUT
  end

  it "parse with freeze: true freezes the containers, the strings and the keys" do
    result = zr(<<~'RUBY')
      require "json"

      a = JSON.parse('[1, "s", {"k": "v"}]', freeze: true)
      p a.frozen?
      p a[1].frozen?
      p a[2].frozen?
      p a[2].keys.first.frozen?
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
      true
    OUT
  end

  it "a document handed straight to parse stays rooted for the whole walk" do
    result = zr(<<~'RUBY')
      # The parser walks its input in place while allocating every container and
      # string it builds, so a document handed straight in -- `JSON.parse
      # File.read(path)`, or any expression whose result nothing else holds -- has to
      # stay rooted for the whole walk. It did not: the first collection under the
      # parse left the cursor reading freed memory, which reads as a parse error
      # whose message varies run to run, and as a segfault once the document is large
      # enough. Sized so the parse itself collects; smaller documents finish before
      # the first one and prove nothing.
      require "json"
      require "strscan"

      def build(n)
        parts = []
        i = 0
        while i < n
          parts << "{\"id\":" + i.to_s + ",\"name\":\"feature-" + i.to_s +
                   "\",\"tags\":[\"a\",\"b\",\"c\"],\"pos\":[-63.121807,46.233965]}"
          i = i + 1
        end
        "[" + parts.join(",") + "]"
      end

      # the source is a temp: nothing but the argument slot holds it across the parse
      doc = JSON.parse(build(80000))
      p doc.length
      p doc[0]["id"]
      p doc[0]["name"]
      p doc[79999]["name"]
      p doc[1234]["tags"]
      p doc[1234]["pos"]

      # a scanner over a temp source borrows the same way
      sc = StringScanner.new(build(50))
      p sc.scan(/\[\{"id":\d+/)
    RUBY

    _(result).must_answer <<~'OUT'
      80000
      0
      "feature-0"
      "feature-79999"
      ["a", "b", "c"]
      [-63.121807, 46.233965]
      "[{\"id\":0"
    OUT
  end

  it "every hostile document answers a value or raises something a program can rescue" do
    result = zr(<<~'RUBY')
      # Every hostile shape the JSON parser has to survive, as ANSWERS rather than
      # as a promise. The point of the file is that none of these ends the process:
      # each row is either a value or a Ruby exception, and the golden pins which.
      # It found real defects rather than confirming a design.
      #
      # ONE ROW IS A DECIDED DIVERGENCE and it is not here: a document nested past
      # 10,000 deep. Ruby's parser keeps its own stack and reads a million-deep
      # document with `max_nesting: false`; this one recurses, so it refuses past
      # a ceiling far short of the frames the stack holds. A loud NestingError
      # beats ending the process.

      require "json"

      def show(name)
        r = yield
        puts "#{name}\t#{r.inspect}"
      rescue Exception => e
        puts "#{name}\t#{e.class}: #{e.message}"
      end

      # --- Truncation, at every position a document has ------------------------
      [
        "{", "}", "[", "]", "\"", ",", ":", "{\"", "{\"a", "{\"a\"", "{\"a\":",
        "{\"a\":1", "[1", "[1,", "[\"", "\"\\\\", "\"\\\\u", "\"\\\\u0",
        "\"\\\\ud8", "-", "0.", "1e", "1e+", "1E-", "0x", "tr", "fal", "nul"
      ].each do |frag|
        show("truncated #{frag.inspect}") { JSON.parse(frag) }
      end

      # --- Empty and blank -----------------------------------------------------
      show("empty") { JSON.parse("") }
      show("space only") { JSON.parse("   \n\t ") }
      show("comment only") { JSON.parse("// nothing\n") }
      show("block comment only") { JSON.parse("/* nothing */") }
      show("unterminated block comment") { JSON.parse("[1] /* x") }
      show("nul byte") { JSON.parse("[1]\0") }
      show("bom") { JSON.parse("﻿[1]") }

      # --- Numbers, including the ones that overflow ---------------------------
      show("huge exponent") { JSON.parse("[1e400]").first }
      show("huge negative exponent") { JSON.parse("[1e-400]").first }
      show("absurd exponent") { JSON.parse("[1e999999999]").first }
      show("absurd negative exponent") { JSON.parse("[1e-999999999]").first }
      show("exponent overflows i32") { JSON.parse("[1e99999999999999999999]").first }
      show("long integer") { JSON.parse("[#{'9' * 400}]").first.to_s.size }
      show("long fraction") { JSON.parse("[0.#{'1' * 400}]").first }
      show("i64 min") { JSON.parse("[-9223372036854775808]").first }
      show("i64 min minus one") { JSON.parse("[-9223372036854775809]").first }
      show("i64 max plus one") { JSON.parse("[9223372036854775808]").first }
      show("negative zero") { JSON.parse("[-0]").first }
      show("negative zero float") { JSON.parse("[-0.0]").first }
      show("leading zero") { JSON.parse("[01]") }
      show("leading zero float") { JSON.parse("[01.5]") }
      show("bare minus") { JSON.parse("[-]") }
      show("bare dot") { JSON.parse("[.5]") }
      show("trailing dot") { JSON.parse("[1.]") }
      show("plus sign") { JSON.parse("[+1]") }
      show("two dots") { JSON.parse("[1.2.3]") }
      show("hex") { JSON.parse("[0x10]") }
      show("infinity word") { JSON.parse("[Infinity]") }
      show("nan word") { JSON.parse("[NaN]") }
      show("negative infinity") { JSON.parse("[-Infinity]") }

      # --- Strings and escapes -------------------------------------------------
      show("bad escape") { JSON.parse('"\\q"') }
      show("short unicode escape") { JSON.parse('"\\u12"') }
      show("non-hex unicode escape") { JSON.parse('"\\uZZZZ"') }
      show("lone high surrogate") { JSON.parse('"\\ud800"') }
      show("lone low surrogate") { JSON.parse('"\\udc00"') }
      show("reversed surrogates") { JSON.parse('"\\udc00\\ud800"') }
      show("valid surrogate pair") { JSON.parse('"\\ud83d\\ude00"') }
      show("high surrogate then escape") { JSON.parse('"\\ud800\\n"') }
      show("escaped nul") { JSON.parse('"\\u0000"').bytes }
      show("raw control byte") { JSON.parse(%Q{"\x01"}) }
      show("escaped solidus") { JSON.parse('"\\/"') }

      # What a message QUOTES BACK: from the offending byte to the first
      # whitespace, capped at 32. Not one byte, and not the rest of the input --
      # `[x]` reaches the `]` because nothing separates them, and the same `x` on
      # its own line stops at the newline.
      show("quote to the closer") { JSON.parse("[x]") }
      show("quote stops at nl") { JSON.parse("[\nx\n]") }
      show("quote stops at space") { JSON.parse("[\nx ]") }
      show("quote stops at tab") { JSON.parse("[\nx\t]") }
      show("quote caps at 32") { JSON.parse("[\n#{"x" * 50}\n]") }
      show("long string") { JSON.parse(%Q{"#{'a' * 100_000}"}).size }
      show("deep escapes") { JSON.parse(%Q{"#{'\\n' * 10_000}"}).size }

      # --- Structure -----------------------------------------------------------
      show("duplicate keys") { JSON.parse('{"a":1,"a":2}') }
      show("non-string key") { JSON.parse("{1:2}") }
      show("missing colon") { JSON.parse('{"a" 1}') }
      show("missing value") { JSON.parse('{"a":}') }
      show("double comma") { JSON.parse("[1,,2]") }
      show("leading comma") { JSON.parse("[,1]") }
      show("trailing comma off") { JSON.parse("[1,]") }
      show("trailing comma on") { JSON.parse("[1,]", allow_trailing_comma: true) }
      show("object trailing comma on") { JSON.parse('{"a":1,}', allow_trailing_comma: true) }
      show("only a comma on") { JSON.parse("[,]", allow_trailing_comma: true) }
      show("mismatched close") { JSON.parse("[1}") }
      show("extra close") { JSON.parse("[1]]") }
      show("two documents") { JSON.parse("[1][2]") }
      show("empty containers") { JSON.parse("[[],{},[{}]]") }
      show("deep but legal") { JSON.parse("[" * 99 + "]" * 99).flatten.size }
      show("one past the default") { JSON.parse("[" * 101 + "]" * 101) }

      # --- Options under stress ------------------------------------------------
      show("max_nesting 0") { JSON.parse("[" * 150 + "]" * 150, max_nesting: 0).class }
      show("max_nesting nil") { JSON.parse("[[1]]", max_nesting: nil).class }
      show("max_nesting negative") { JSON.parse("[[1]]", max_nesting: -1).class }
      show("symbolize deep") { JSON.parse('{"a":{"b":1}}', symbolize_names: true) }
      show("freeze deep") do
        v = JSON.parse('{"a":["b"]}', freeze: true)
        [v.frozen?, v.keys.first.frozen?, v["a"].frozen?, v["a"].first.frozen?]
      end
      show("object_class refusing") { JSON.parse('{"a":1}', object_class: Integer) }
      show("array_class refusing") { JSON.parse("[1]", array_class: Integer) }
      show("decimal_class refusing") { JSON.parse("[1.5]", decimal_class: Integer) }

      # --- Bytes that are not text --------------------------------------------
      show("invalid utf-8") { JSON.parse("[\"\xFF\"]".b) }
      show("truncated utf-8") { JSON.parse("[\"\xE3\x81\"]".b) }
      # NOT here: a high byte OUTSIDE a string. Ruby quotes the raw byte back in
      # the message, so the message itself is not valid UTF-8; zr's message
      # builder takes UTF-8 only and renders the byte U+FFFD. Display only, and
      # `tests/json_message_bytes_are_lossy.rb` records it.

      # --- The whole document is a scalar --------------------------------------
      show("bare true") { JSON.parse("true") }
      show("bare null") { JSON.parse("null") }
      show("bare number") { JSON.parse("42") }
      show("bare string") { JSON.parse('"x"') }
      show("bare word") { JSON.parse("nope") }
    RUBY

    _(result).must_answer <<~'OUT'
      truncated "{"	JSON::ParserError: expected object key, got EOF at line 1 column 2
      truncated "}"	JSON::ParserError: unexpected character: '}' at line 1 column 1
      truncated "["	JSON::ParserError: unexpected end of input at line 1 column 2
      truncated "]"	JSON::ParserError: unexpected character: ']' at line 1 column 1
      truncated "\""	JSON::ParserError: unexpected end of input, expected closing " at line 1 column 2
      truncated ","	JSON::ParserError: unexpected character: ',' at line 1 column 1
      truncated ":"	JSON::ParserError: unexpected character: ':' at line 1 column 1
      truncated "{\""	JSON::ParserError: unexpected end of input, expected closing " at line 1 column 3
      truncated "{\"a"	JSON::ParserError: unexpected end of input, expected closing " at line 1 column 4
      truncated "{\"a\""	JSON::ParserError: expected ':' after object key at line 1 column 5
      truncated "{\"a\":"	JSON::ParserError: unexpected end of input at line 1 column 6
      truncated "{\"a\":1"	JSON::ParserError: expected ',' or '}' after object value, got: EOF at line 1 column 7
      truncated "[1"	JSON::ParserError: expected ',' or ']' after array value at line 1 column 3
      truncated "[1,"	JSON::ParserError: unexpected end of input at line 1 column 4
      truncated "[\""	JSON::ParserError: unexpected end of input, expected closing " at line 1 column 3
      truncated "\"\\\\"	JSON::ParserError: unexpected end of input, expected closing " at line 1 column 4
      truncated "\"\\\\u"	JSON::ParserError: unexpected end of input, expected closing " at line 1 column 5
      truncated "\"\\\\u0"	JSON::ParserError: unexpected end of input, expected closing " at line 1 column 6
      truncated "\"\\\\ud8"	JSON::ParserError: unexpected end of input, expected closing " at line 1 column 7
      truncated "-"	JSON::ParserError: invalid number: '-' at line 1 column 1
      truncated "0."	JSON::ParserError: invalid number: '0.' at line 1 column 1
      truncated "1e"	JSON::ParserError: invalid number: '1e' at line 1 column 1
      truncated "1e+"	JSON::ParserError: invalid number: '1e+' at line 1 column 1
      truncated "1E-"	JSON::ParserError: invalid number: '1E-' at line 1 column 1
      truncated "0x"	JSON::ParserError: unexpected token at end of stream 'x' at line 1 column 2
      truncated "tr"	JSON::ParserError: unexpected token 'tr' at line 1 column 1
      truncated "fal"	JSON::ParserError: unexpected token 'fal' at line 1 column 1
      truncated "nul"	JSON::ParserError: unexpected token 'nul' at line 1 column 1
      empty	JSON::ParserError: unexpected end of input at line 1 column 1
      space only	JSON::ParserError: unexpected end of input at line 2 column 3
      comment only	JSON::ParserError: unexpected end of input at line 2 column 1
      block comment only	JSON::ParserError: unexpected end of input at line 1 column 14
      unterminated block comment	JSON::ParserError: unterminated comment, expected closing '*/' at line 1 column 5
      nul byte	JSON::ParserError: unexpected token at end of stream  at line 1 column 4
      bom	JSON::ParserError: unexpected character: '﻿[1]' at line 1 column 1
      huge exponent	Infinity
      huge negative exponent	0.0
      absurd exponent	Infinity
      absurd negative exponent	0.0
      exponent overflows i32	Infinity
      long integer	400
      long fraction	0.1111111111111111
      i64 min	-9223372036854775808
      i64 min minus one	-9223372036854775809
      i64 max plus one	9223372036854775808
      negative zero	0
      negative zero float	-0.0
      leading zero	JSON::ParserError: invalid number: '01]' at line 1 column 2
      leading zero float	JSON::ParserError: invalid number: '01.5]' at line 1 column 2
      bare minus	JSON::ParserError: invalid number: '-]' at line 1 column 2
      bare dot	JSON::ParserError: unexpected character: '.5]' at line 1 column 2
      trailing dot	JSON::ParserError: invalid number: '1.]' at line 1 column 2
      plus sign	JSON::ParserError: unexpected character: '+1]' at line 1 column 2
      two dots	JSON::ParserError: expected ',' or ']' after array value at line 1 column 5
      hex	JSON::ParserError: expected ',' or ']' after array value at line 1 column 3
      infinity word	JSON::ParserError: unexpected token 'Infinity]' at line 1 column 2
      nan word	JSON::ParserError: unexpected token 'NaN]' at line 1 column 2
      negative infinity	JSON::ParserError: invalid number: '-Infinity]' at line 1 column 2
      bad escape	JSON::ParserError: invalid escape character in string: '\q"' at line 1 column 2
      short unicode escape	JSON::ParserError: incomplete unicode character escape sequence at '\u12"' at line 1 column 2
      non-hex unicode escape	JSON::ParserError: incomplete unicode character escape sequence at '\uZZZZ"' at line 1 column 2
      lone high surrogate	JSON::ParserError: incomplete surrogate pair at '\ud800"' at line 1 column 2
      lone low surrogate	"\xED\xB0\x80"
      reversed surrogates	JSON::ParserError: incomplete surrogate pair at '\ud800"' at line 1 column 8
      valid surrogate pair	"😀"
      high surrogate then escape	JSON::ParserError: incomplete surrogate pair at '\ud800\n"' at line 1 column 2
      escaped nul	[0]
      raw control byte	JSON::ParserError: invalid ASCII control character in string: '"' at line 1 column 2
      escaped solidus	"/"
      quote to the closer	JSON::ParserError: unexpected character: 'x]' at line 1 column 2
      quote stops at nl	JSON::ParserError: unexpected character: 'x' at line 2 column 1
      quote stops at space	JSON::ParserError: unexpected character: 'x' at line 2 column 1
      quote stops at tab	JSON::ParserError: unexpected character: 'x' at line 2 column 1
      quote caps at 32	JSON::ParserError: unexpected character: 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx' at line 2 column 1
      long string	100000
      deep escapes	10000
      duplicate keys	{"a" => 2}
      non-string key	JSON::ParserError: expected object key, got '1:2}' at line 1 column 2
      missing colon	JSON::ParserError: expected ':' after object key at line 1 column 6
      missing value	JSON::ParserError: unexpected character: '}' at line 1 column 6
      double comma	JSON::ParserError: unexpected character: ',2]' at line 1 column 4
      leading comma	JSON::ParserError: unexpected character: ',1]' at line 1 column 2
      trailing comma off	JSON::ParserError: unexpected character: ']' at line 1 column 4
      trailing comma on	[1]
      object trailing comma on	{"a" => 1}
      only a comma on	JSON::ParserError: unexpected character: ',]' at line 1 column 2
      mismatched close	JSON::ParserError: expected ',' or ']' after array value at line 1 column 3
      extra close	JSON::ParserError: unexpected token at end of stream ']' at line 1 column 4
      two documents	JSON::ParserError: unexpected token at end of stream '[2]' at line 1 column 4
      empty containers	[[], {}, [{}]]
      deep but legal	0
      one past the default	[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]
      max_nesting 0	Array
      max_nesting nil	Array
      max_nesting negative	JSON::NestingError: nesting of 1 is too deep
      symbolize deep	{a: {b: 1}}
      freeze deep	[true, true, true, true]
      object_class refusing	NoMethodError: undefined method 'new' for class Integer
      array_class refusing	NoMethodError: undefined method 'new' for class Integer
      decimal_class refusing	[nil]
      invalid utf-8	["\xFF"]
      truncated utf-8	["\xE3\x81"]
      bare true	true
      bare null	nil
      bare number	42
      bare string	"x"
      bare word	JSON::ParserError: unexpected token 'nope' at line 1 column 1
    OUT
  end

  it "-0 parses as Integer, and a trailing comma and a trailing comment are accepted" do
    result = zr(<<~'RUBY')
      # Three parser rows: `-0` parses as INTEGER 0, `allow_trailing_comma: true`
      # admits `[1,]`, and trailing `// c` after the document is accepted.
      # (Found by the 2026-08-24 probe sweep.)
      require "json"
      def show
        p yield
      rescue Exception => e
        puts "#{e.class}: #{e.message}"
      end
      show { JSON.parse("[-0]").first }
      show { JSON.parse("[1,]", allow_trailing_comma: true) }
      show { JSON.parse("[1] // c") }
    RUBY

    _(result).must_answer <<~'OUT'
      0
      [1]
      [1]
    OUT
  end

  it "tens of thousands of generated documents each answer or raise, and none ends the process" do
    result = zr(<<~'RUBY')
      # The GENERATED half of the parser's safety net: tens of thousands of
      # inputs nobody wrote by hand, checked for the one property that matters at
      # this scale -- the program is still running afterwards.
      #
      # It asserts almost nothing about VALUES. `json_parser_edge_cases.rb` pins
      # those, row by row, against ruby's own answers. What this file proves is
      # that no input ends the process, hangs it, or reads past the end of a
      # buffer: every row answers a value or raises something a program can
      # rescue, and the counts at the end are the same under both engines.
      #
      # The generator is deterministic (a fixed seed), so a failure here is
      # reproducible rather than a story about one unlucky run.
      #
      # Two shapes found real defects when this was written: a `\u` escape
      # truncated by the end of input reported the wrong error, and a stray NUL
      # after a document quoted a byte ruby does not.

      require "json"

      SEED = 20_260_826
      rng = Random.new(SEED)

      # `outcome` collapses a run to one of four words, so the counts can be
      # compared without pinning a message that is allowed to differ.
      def outcome
        yield
        "value"
      rescue JSON::NestingError
        "nesting"
      rescue JSON::ParserError
        "parser"
      rescue StandardError => e
        "other:#{e.class}"
      end

      tally = Hash.new(0)

      # --- Random bytes, every length from empty to sixty-four -----------------
      64.times do |len|
        200.times do
          bytes = Array.new(len) { rng.rand(256) }.pack("C*")
          tally[outcome { JSON.parse(bytes) }] += 1
        end
      end

      # --- Random bytes drawn only from JSON's own alphabet --------------------
      # Far more likely to reach deep into the parser than uniform noise.
      ALPHABET = %w<{ } [ ] " : , 0 1 9 - + . e E t f n u l r s a i \\ / * space
                    tab newline>.map do |w|
        case w
        when "space" then " "
        when "tab" then "\t"
        when "newline" then "\n"
        else w
        end
      end

      40.times do |len|
        300.times do
          s = Array.new(len) { ALPHABET.sample(random: rng) }.join
          tally[outcome { JSON.parse(s) }] += 1
        end
      end

      # --- Valid documents, mutated one byte at a time -------------------------
      SEEDS = [
        '{"a":1}',
        '[1,2,3]',
        '{"a":[1,{"b":null}],"c":"é"}',
        '[-1.5e-3,true,false,null,""]',
        '{"k":"😀","n":123456789012345678901234567890}',
        '[[[[[1]]]]]',
        '{"a":{"b":{"c":{"d":[]}}}}'
      ].freeze

      SEEDS.each do |doc|
        doc.bytesize.times do |i|
          # Deleted.
          tally[outcome { JSON.parse(doc.b.dup.tap { |d| d.slice!(i) }) }] += 1
          # Replaced by a byte from the alphabet, and by a random one.
          [ALPHABET.sample(random: rng).bytes.first, rng.rand(256)].each do |b|
            m = doc.b.dup
            m.setbyte(i, b)
            tally[outcome { JSON.parse(m) }] += 1
          end
          # Truncated here.
          tally[outcome { JSON.parse(doc.byteslice(0, i)) }] += 1
        end
      end

      # --- Numbers at every boundary a parser has ------------------------------
      NUMBERS = [
        "0", "-0", "0.0", "-0.0", "1e0", "1E0", "1e+0", "1e-0",
        "9223372036854775807", "9223372036854775808", "-9223372036854775808",
        "-9223372036854775809", "1" + "0" * 400, "0." + "0" * 400 + "1",
        "1e308", "1e309", "1e-323", "1e-324", "1e999999999", "-1e999999999",
        "1e" + "9" * 40, "0e0", "-0e-0", "00", "01", "1.", ".1", "+1", "1e",
        "1e+", "--1", "1-1", "0x1", "1_000", "Infinity", "-Infinity", "NaN"
      ].freeze

      NUMBERS.each do |n|
        tally[outcome { JSON.parse("[#{n}]") }] += 1
        tally[outcome { JSON.parse(n) }] += 1
        tally[outcome { JSON.parse("[#{n}]", allow_nan: true) }] += 1
      end

      # --- Escapes at every boundary -------------------------------------------
      %w[a b f n r t u v 0 / \\ " ' x z].each do |e|
        tally[outcome { JSON.parse(%Q{"\\#{e}"}) }] += 1
      end
      (0..0xFFFF).step(97) do |cp|
        tally[outcome { JSON.parse(format('"\\u%04x"', cp)) }] += 1
      end

      # --- Nesting, either side of every limit ---------------------------------
      # 2,001 is NOT here: past zr's stack ceiling the two engines deliberately
      # disagree, and `tests/json_nesting_is_bounded_by_the_stack.rb` is where
      # that row lives. Everything below the ceiling must agree exactly.
      [0, 1, 2, 99, 100, 101, 1_999, 2_000].each do |n|
        doc = "[" * n + "]" * n
        tally[outcome { JSON.parse(doc) }] += 1
        tally[outcome { JSON.parse(doc, max_nesting: false) }] += 1
        tally[outcome { JSON.parse("[" * n + "1" + "]" * n, max_nesting: false) }] += 1
      end

      # --- Big and repetitive --------------------------------------------------
      tally[outcome { JSON.parse("[#{Array.new(50_000, 1).join(',')}]").size } ] += 1
      tally[outcome { JSON.parse(%Q{"#{'x' * 500_000}"}).size }] += 1
      tally[outcome { JSON.parse("{#{Array.new(20_000) { |i| %Q{"k#{i}":#{i}} }.join(',')}}").size }] += 1
      tally[outcome { JSON.parse("[" + '"\\n"' * 50_000 + "]").size }] += 1

      # --- Round trip: whatever parses must generate and parse back the same ---
      round = 0
      SEEDS.each do |doc|
        v = JSON.parse(doc)
        round += 1 if JSON.parse(JSON.generate(v)) == v
        round += 1 if JSON.parse(JSON.pretty_generate(v)) == v
        round += 1 if JSON.parse(JSON.generate(v, ascii_only: true)) == v
      end

      puts "outcomes"
      tally.keys.sort.each { |k| puts "  #{k}\t#{tally[k]}" }
      puts "round trips\t#{round}"
      puts "still running\ttrue"
    RUBY

    _(result).must_answer <<~'OUT'
      outcomes
        nesting	2
        parser	25328
        value	920
      round trips	21
      still running	true
    OUT
  end

  it "a generate and parse round trip holds, and symbolize_names: keys the result by symbol" do
    result = zr(<<~'RUBY')
      # The json extension links into the binary: generation and parsing both run
      # native code the link line has to carry.
      require "json"
      doc = { "name" => "zr", "tags" => %w[ruby aot], "n" => 42, "ok" => true, "nil" => nil }
      text = JSON.generate(doc)
      puts text
      p JSON.parse(text) == doc
      puts JSON.pretty_generate("a" => [1, 2])
      p JSON.parse('{"deep":{"list":[1,2,3]}}', symbolize_names: true)
    RUBY

    _(result).must_answer <<~'OUT'
      {"name":"zr","tags":["ruby","aot"],"n":42,"ok":true,"nil":null}
      true
      {
        "a": [
          1,
          2
        ]
      }
      {deep: {list: [1, 2, 3]}}
    OUT
  end

  it "requiring json gives every object to_json, not only the JSON.generate entry point" do
    result = zr(<<~'RUBY')
      # `require "json"` gives every object a `#to_json`, not just the explicit
      # `JSON.generate`/`JSON.dump` entry points.
      require "json"

      p({a: 1}.to_json)
      p({a: {b: [1, nil]}}.to_json)
      p [1, "two", nil, true, false].to_json
      p 1.to_json, 1.5.to_json, "hi".to_json, :sym.to_json
      p nil.to_json, true.to_json, false.to_json

      # Anything else encodes as its `to_s`, as a JSON STRING.
      p (1..3).to_json
      p Struct.new(:x).new(1).to_json
      p Object.new.to_json.class

      # ...and the state argument a container threads through is accepted.
      p({a: 1}.to_json(nil))
      p [1].to_json(nil)

      # Round-tripping through the parser gives the value back.
      p JSON.parse({"a" => [1, {"b" => nil}]}.to_json)
      p JSON.parse("[1,2]").to_json
    RUBY

    _(result).must_answer <<~'OUT'
      "{\"a\":1}"
      "{\"a\":{\"b\":[1,null]}}"
      "[1,\"two\",null,true,false]"
      "1"
      "1.5"
      "\"hi\""
      "\"sym\""
      "null"
      "true"
      "false"
      "\"1..3\""
      "\"#<struct x=1>\""
      String
      "{\"a\":1}"
      "[1]"
      {"a" => [1, {"b" => nil}]}
      "[1,2]"
    OUT
  end

  it "native half still works through its ruby half" do
    result = zr(<<~'RUBY')
      # Loading one stdlib gem must not disturb another: `require "strscan"`
      # then `require "json"` still both work end to end.

      require "strscan"
      require "json"
      s = StringScanner.new("hello world")
      p s.scan(/\w+/)
      p s.rest
      p JSON.dump({ "a" => 1 })
    RUBY

    _(result).must_answer <<~'OUT'
      "hello"
      " world"
      "{\"a\":1}"
    OUT
  end

  it "poly each returns receiver" do
    result = zr(<<~'RUBY')
      # `each` answers the receiver, and a boxed receiver is no different -- but the
      # call was typed only when the analyzer could prove the value carried a
      # container, so a JSON.parse result (a native call returning an untyped value)
      # left the chain with nothing to dispatch on and was refused at compile time.
      require "json"

      p JSON.parse("[]").each {}.size
      p JSON.parse("[1,2]").each {}.size
      p JSON.parse("[1,2]").each { |x| x }.size
      p JSON.parse("{\"a\":1}").each {}.size
      p JSON.parse("[1,2]").each_with_index {}.size
      p JSON.parse("[[1],[2]]").each { |r| }.first
      p JSON.parse("[1,2]").each {}.class

      # each_entry yields what each yields, and reverse_each the same from the other
      # end -- both answer the receiver too
      p JSON.parse("[]").each_entry {}.size
      p JSON.parse("{\"a\":1}").each_entry { |e| p e }.size
      p JSON.parse("[1,2]").reverse_each {}.size
      JSON.parse("[1,2,3]").reverse_each { |x| p x }
      JSON.parse("{\"a\":1,\"b\":2}").reverse_each { |k, v| p k }

      # a boxed value with no `each` raises where CRuby raises, rather than
      # iterating zero times and handing the receiver back
      begin
        JSON.parse("5").each {}
      rescue => e
        p e.class
      end
    RUBY

    _(result).must_answer <<~'OUT'
      0
      2
      2
      1
      2
      [1]
      Array
      0
      ["a", 1]
      1
      2
      3
      2
      1
      "b"
      "a"
      NoMethodError
    OUT
  end

  it "probe roundtrip" do
    result = zr(<<~'RUBY')
      # The cycle this program builds on purpose, and the census it leaves
      # behind. A cycle alive at exit is not a defect: it is a ring the
      # program never broke, so the census below is recorded as an
      # observation rather than gated on.
      #
      # The three `a << a` rings the cycle rows build, plus the two more that the Marshal and YAML round trips revive.
      # At exit: cycle leak: 5 objects (Array x5)
      # Differential probe: ROUND-TRIP INTEGRITY.
      #
      # For every serializer and every container, asserts that a value survives
      # its own encoding -- `load(dump(x)) == x`, sizes preserved, key identity
      # preserved. A GOLDEN: the `.expected` beside it is ruby 4.0.6's own
      # answers.
      #
      # This is the highest-yield way to catch SILENT corruption, because it needs
      # no reference output to compare against: a value that does not survive its
      # own serializer is wrong on its own terms, and the row says so on both
      # engines. The differential half then catches the cases where zr and ruby
      # BOTH answer, differently.
      #
      # The Hash key-identity rows exist because a table keyed on a user `hash`
      # alone silently held one entry where two were stored, and read back
      # another key's value.

      require "json"
      require "yaml"
      require "set"
      require "stringio"

      ROWS = {}

      def probe(name, &blk) = ROWS[name] = blk

      # Rows zr does not answer yet, each naming the gap that tracks it. A carved
      # row is left OUT of the output rather than recorded wrong. When a gap is
      # promoted, delete its entry here and re-bless; the row comes back.
      SKIP = {
        "marshal array ivar" => "tests/gaps/marshal_carries_an_array_s_ivars.rb",
      }.freeze

      VALUES = {
        "nil" => nil,
        "true" => true,
        "int" => 42,
        "negzero" => -0,
        "bignum" => 2**70,
        "float" => 1.5,
        "float_e" => 1e100,
        "string" => "hi",
        "string_utf8" => "héllo",
        "string_binary" => "\xff\xfe".b,
        "symbol" => :sym,
        "array" => [1, [2, [3]]],
        "hash" => { "a" => 1, "b" => { "c" => 2 } },
        "empty" => [],
        "nested_empty" => { "a" => [], "b" => {} },
      }.freeze

      VALUES.each do |name, v|
        probe("marshal:#{name}") { Marshal.load(Marshal.dump(v)) == v }
      end

      VALUES.each do |name, v|
        # JSON has no Symbol or binary-string tier, so those rows read as their
        # JSON projection rather than as equality -- still a round trip, of the
        # thing JSON actually carries.
        probe("json:#{name}") { JSON.parse(JSON.generate([v])).first.inspect }
      end

      VALUES.each do |name, v|
        probe("yaml:#{name}") { YAML.unsafe_load(YAML.dump(v)) == v }
      end

      # --- Structural sharing ---------------------------------------------------
      # The CYCLE rows live at the very bottom: they are the ones that can take the
      # process down, and every row after an abort reads as `<no row>` rather than
      # as a finding.
      probe("marshal shared") do
        inner = [1]
        outer = [inner, inner]
        r = Marshal.load(Marshal.dump(outer))
        r[0].equal?(r[1])
      end
      probe("yaml shared") do
        inner = [1]
        r = YAML.unsafe_load(YAML.dump([inner, inner]))
        r[0].equal?(r[1])
      end

      # --- Ivars and extensions ride along --------------------------------------
      probe("marshal string ivar") do
        s = +"hi"
        s.instance_variable_set(:@meta, 7)
        Marshal.load(Marshal.dump(s)).instance_variable_get(:@meta)
      end
      probe("marshal array ivar") do
        a = [1]
        a.instance_variable_set(:@meta, 7)
        Marshal.load(Marshal.dump(a)).instance_variable_get(:@meta)
      end
      probe("marshal object ivars") do
        c = Struct.new(:a)
        Marshal.load(Marshal.dump(c.new(1))).a
      end
      probe("marshal encoding") do
        Marshal.load(Marshal.dump("héllo")).encoding.to_s
      end
      probe("marshal binary encoding") do
        Marshal.load(Marshal.dump("\xff".b)).encoding.to_s
      end

      # --- Hash key identity ----------------------------------------------------
      class Colliding
        attr_reader :n

        def initialize(n) = @n = n
        def hash = 7
        def eql?(o) = o.is_a?(Colliding) && o.n == @n
        def ==(o) = eql?(o)
      end

      class OnlyHash
        def hash = 7
      end

      class OnlyEql
        def eql?(_o) = true
        def ==(_o) = true
      end

      probe("hash colliding size") do
        h = {}
        h[Colliding.new(1)] = "a"
        h[Colliding.new(2)] = "b"
        h.size
      end
      probe("hash colliding read") do
        h = {}
        h[Colliding.new(1)] = "a"
        h[Colliding.new(2)] = "b"
        h[Colliding.new(1)]
      end
      probe("hash colliding key?") do
        h = { Colliding.new(1) => "a" }
        [h.key?(Colliding.new(1)), h.key?(Colliding.new(2))]
      end
      probe("hash colliding delete") do
        h = {}
        h[Colliding.new(1)] = "a"
        h[Colliding.new(2)] = "b"
        h.delete(Colliding.new(1))
        [h.size, h.values]
      end
      probe("uniq colliding") { [Colliding.new(1), Colliding.new(2), Colliding.new(1)].uniq.size }
      probe("set colliding") { Set.new([Colliding.new(1), Colliding.new(2), Colliding.new(1)]).size }
      probe("group_by colliding") do
        [1, 2, 3].group_by { Colliding.new(1) }.size
      end
      probe("only hash") do
        h = {}
        h[OnlyHash.new] = 1
        h[OnlyHash.new] = 2
        h.size
      end
      probe("only eql") do
        h = {}
        h[OnlyEql.new] = 1
        h[OnlyEql.new] = 2
        h.size
      end
      probe("compare_by_identity") do
        k = Colliding.new(1)
        h = {}.compare_by_identity
        h[k] = 1
        h[Colliding.new(1)] = 2
        [h.size, h[k]]
      end
      probe("string key dup") do
        h = {}
        h[+"k"] = 1
        h[+"k"] = 2
        [h.size, h["k"]]
      end
      probe("frozen string key") do
        h = { "k" => 1 }
        h.keys.first.frozen?
      end
      probe("float int keys") do
        h = { 1 => "int", 1.0 => "float" }
        [h.size, h[1], h[1.0]]
      end
      probe("array key") do
        h = { [1, [2]] => "v" }
        h[[1, [2]]]
      end
      probe("hash key") do
        h = { { "a" => 1 } => "v" }
        [h[{ "a" => 1 }], h[{ "b" => 1 }].inspect]
      end
      probe("range key") { { (1..2) => "v" }[(1..2)] }
      probe("regexp key") { { /a/i => "v" }[/a/i] }
      probe("mutated key") do
        k = +"k"
        h = { k => 1 }
        k << "!"
        [h.size, h["k"].inspect, h["k!"].inspect, h.rehash && h["k!"]]
      end

      # --- StringIO round trips -------------------------------------------------
      probe("stringio append") do
        s = StringIO.new(+"abc", "a")
        s.write("d")
        s.string
      end
      probe("stringio truncate mode") do
        s = StringIO.new(+"abc", "w")
        s.string
      end
      probe("stringio read only write") do
        StringIO.new(+"abc", "r").write("d")
      end
      probe("stringio append read") do
        StringIO.new(+"abc", "a").read
      end

      # --- Cycles: LAST, because these are the rows that can abort the process ---
      probe("marshal cycle") do
        a = []
        a << a
        r = Marshal.load(Marshal.dump(a))
        r[0].equal?(r)
      end
      probe("json cycle") do
        a = []
        a << a
        JSON.generate(a)
      end
      probe("yaml cycle") do
        a = []
        a << a
        r = YAML.unsafe_load(YAML.dump(a))
        r[0].equal?(r)
      end

      ROWS.each do |name, fn|
        next if SKIP.key?(name)

        r = begin
          v = fn.call
          "ok #{v.inspect}"
        rescue Exception => e
          "#{e.class}: #{e.message}"
        end
        puts "#{name}\t#{r}"
        $stdout.flush
      end
    RUBY

    _(result).must_answer <<~'OUT'
      marshal:nil	ok true
      marshal:true	ok true
      marshal:int	ok true
      marshal:negzero	ok true
      marshal:bignum	ok true
      marshal:float	ok true
      marshal:float_e	ok true
      marshal:string	ok true
      marshal:string_utf8	ok true
      marshal:string_binary	ok true
      marshal:symbol	ok true
      marshal:array	ok true
      marshal:hash	ok true
      marshal:empty	ok true
      marshal:nested_empty	ok true
      json:nil	ok "nil"
      json:true	ok "true"
      json:int	ok "42"
      json:negzero	ok "0"
      json:bignum	ok "1180591620717411303424"
      json:float	ok "1.5"
      json:float_e	ok "1.0e+100"
      json:string	ok "\"hi\""
      json:string_utf8	ok "\"héllo\""
      json:string_binary	JSON::GeneratorError: "\xFF" from ASCII-8BIT to UTF-8
      json:symbol	ok "\"sym\""
      json:array	ok "[1, [2, [3]]]"
      json:hash	ok "{\"a\" => 1, \"b\" => {\"c\" => 2}}"
      json:empty	ok "[]"
      json:nested_empty	ok "{\"a\" => [], \"b\" => {}}"
      yaml:nil	ok true
      yaml:true	ok true
      yaml:int	ok true
      yaml:negzero	ok true
      yaml:bignum	ok true
      yaml:float	ok true
      yaml:float_e	ok true
      yaml:string	ok true
      yaml:string_utf8	ok true
      yaml:string_binary	ok true
      yaml:symbol	ok true
      yaml:array	ok true
      yaml:hash	ok true
      yaml:empty	ok true
      yaml:nested_empty	ok true
      marshal shared	ok true
      yaml shared	ok true
      marshal string ivar	ok 7
      marshal object ivars	TypeError: can't dump anonymous class #<Class:0xADDR>
      marshal encoding	ok "UTF-8"
      marshal binary encoding	ok "ASCII-8BIT"
      hash colliding size	ok 2
      hash colliding read	ok "a"
      hash colliding key?	ok [true, false]
      hash colliding delete	ok [1, ["b"]]
      uniq colliding	ok 2
      set colliding	ok 2
      group_by colliding	ok 1
      only hash	ok 2
      only eql	ok 2
      compare_by_identity	ok [2, 1]
      string key dup	ok [1, 2]
      frozen string key	ok true
      float int keys	ok [2, "int", "float"]
      array key	ok "v"
      hash key	ok ["v", "nil"]
      range key	ok "v"
      regexp key	ok "v"
      mutated key	ok [1, "1", "nil", nil]
      stringio append	ok "abcd"
      stringio truncate mode	ok ""
      stringio read only write	IOError: not opened for writing
      stringio append read	IOError: not opened for reading
      marshal cycle	ok true
      json cycle	JSON::NestingError: nesting of 100 is too deep. Did you try to serialize objects with circular references?
      yaml cycle	ok true
    OUT
  end

  it "require in conditional" do
    result = zr(<<~'RUBY')
      # A `require` is a compile-time directive in Spinel; one that survives into
      # codegen -- indented inside an `if`, a method body, or used in value position
      # -- is a runtime no-op rather than an "unsupported CallNode" hard error.

      if 1 > 0
        require "set"
      end

      def helper
        require "json"
        "ok"
      end

      x = require("set")
      puts helper
      puts "done"
    RUBY

    _(result).must_answer "ok\ndone\n"
  end

  it "require modifier" do
    result = zr(<<~'RUBY')
      # A bare-string `require` followed by a trailing modifier (`rescue`,
      # `if`, ...) used to strand the modifier during require preprocessing and
      # produce a parse error ("unexpected 'rescue'"). The require now degrades
      # to a `nil` expression so the modifier attaches and the program parses.
      # (json/set are stdlib in the reference Ruby, so the rescue is a moot
      # defensive guard there; the program does not use either library.)
      require 'json' rescue nil
      puts "ok1"
      x = 5 rescue nil
      puts x
      require 'set' if false
      puts "ok2"
    RUBY

    _(result).must_answer <<~'OUT'
      ok1
      5
      ok2
    OUT
  end

  it "require same line" do
    result = zr(<<~'RUBY')
      # Regression for #1150 bug 1: `require "x"; code` on one line truncated the
      # trailing code (the whole line was replaced). The code after the require
      # must survive.
      puts "start"
      require "json"; puts JSON.generate([1, 2, 3])
    RUBY

    _(result).must_answer "start\n[1,2,3]\n"
  end

  it "require unsupported lib" do
    result = zr(<<~'RUBY')
      # A `require` of a natively-provided lib (json) is a no-op and the module still
      # works (under SPINEL_REQUIRE_GATE the require also records the feature, enabling
      # JSON). An unsupported stdlib like tmpdir would instead be a compile-time
      # "cannot load such file" under the gate, so it is not exercised here.
      require "json"
      puts JSON.generate([1, 2, 3])
      puts "ok"
    RUBY

    _(result).must_answer "[1,2,3]\nok\n"
  end

  it "require works in non top level positions" do
    result = zr(<<~'RUBY')
      require "ostruct" if RUBY_VERSION
      def make_struct
        require "ostruct"
        OpenStruct.new(a: 1, b: 2).b
      end
      puts make_struct

      begin
        require "set"
      rescue LoadError
        abort "no set"
      end
      puts Set.new([1, 1, 2, 3]).size

      def with_json
        begin
          require "json"
        rescue LoadError
          return "no json"
        end
        JSON.generate({ "k" => 1 })
      end
      puts with_json
    RUBY

    _(result).must_answer <<~'OUT'
      2
      3
      {"k":1}
    OUT
  end

  it "resumable parser takes its source in pieces" do
    result = zr(<<~'RUBY')
      # JSON::ResumableParser takes its source in pieces: a token a piece cuts
      # is read again once the rest comes, partial_value closes the containers
      # still open, and each whole document waits in value.
      require "json"
      pr = JSON::ResumableParser.new
      pr << %q({"user": "george", "role": "ad)
      p pr.parse, pr.eos?, pr.partial_value, pr.rest, pr.partial_value?, pr.value?, pr.parsed_bytes, pr.empty?
      pr << %q(min" }[1, 2, 3])
      p pr.parse, pr.value, pr.parse, pr.value, pr.parse, pr.eos?, pr.empty?
      pr << "123"; p pr.parse, pr.rest; pr << " "; p pr.parse, pr.value
      pr << "[1, [2, 3,"; p pr.parse, pr.partial_value, (pr.value rescue $!)
      pr.clear; pr << "tr"; p pr.parse, pr.rest; pr << "ue x"; p pr.parse, pr.value; p (pr.parse rescue $!), pr.rest
      pr.clear; pr << "/* c"; p pr.parse; pr << " */ 1 "; p pr.parse, pr.value
      pr2 = JSON::ResumableParser.new(symbolize_names: true); pr2 << %({"a":1}); p pr2.parse, pr2.value
      pr3 = JSON::ResumableParser.new
      ["[", " {\"k\" : [1 , 2.5", "e3 ] , \"s\": \"a\\u00", "e9\" } ", "]", " -"].each { |piece| pr3 << piece; p [piece, pr3.parse, pr3.partial_value, pr3.rest] }
      p pr3.value? && pr3.value
      pr4 = JSON::ResumableParser.new
      pr4 << "[1]\n[2]\n{\"x\": nu"
      got = []
      got << pr4.value while pr4.parse
      p got, pr4.partial_value, pr4.partial_value?, pr4.parsed_bytes
      pr4 << "ll}"; p pr4.parse, pr4.value, pr4.empty?
      p((JSON::ResumableParser.new.tap { |x| x << "[1,]" }.parse rescue $!))

    RUBY

    _(result).must_answer <<~'OUT'
      false
      false
      {"user" => "george", "role" => nil}
      "\"ad"
      true
      false
      30
      false
      true
      {"user" => "george", "role" => "admin"}
      true
      [1, 2, 3]
      false
      true
      true
      false
      "123"
      true
      123
      false
      [1, [2, 3]]
      #<ArgumentError: no ready value>
      false
      "tr"
      true
      true
      #<JSON::ParserError: unexpected character: 'x'>
      "x"
      false
      true
      1
      true
      {a: 1}
      ["[", false, nil, "["]
      [" {\"k\" : [1 , 2.5", false, [{"k" => [1]}], "2.5"]
      ["e3 ] , \"s\": \"a\\u00", false, [{"k" => [1, 2500.0], "s" => nil}], "\"a\\u00"]
      ["e9\" } ", false, [{"k" => [1, 2500.0], "s" => "aé"}], ""]
      ["]", true, [{"k" => [1, 2500.0], "s" => "aé"}], ""]
      [" -", false, nil, "-"]
      false
      [[1], [2]]
      {"x" => nil}
      true
      8
      true
      {"x" => nil}
      true
      #<JSON::ParserError: unexpected character: ']'>
    OUT
  end

  it "user to json nested" do
    result = zr(<<~'RUBY')
      require "json"

      class Point
        def initialize(x, y)
          @x = x
          @y = y
        end

        def to_json(*args)
          { x: @x, y: @y }.to_json(*args)
        end
      end

      p Point.new(1, 2).to_json
      p JSON.generate({ points: [Point.new(1, 2), Point.new(3, 4)], n: 2 })
      puts JSON.pretty_generate([Point.new(5, 6)])
    RUBY

    _(result).must_answer <<~'OUT'
      "{\"x\":1,\"y\":2}"
      "{\"points\":[{\"x\":1,\"y\":2},{\"x\":3,\"y\":4}],\"n\":2}"
      [
        {
          "x": 5,
          "y": 6
        }
      ]
    OUT
  end
end
