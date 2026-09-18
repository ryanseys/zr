# frozen_string_literal: true

require "spec_helper"

describe "Hash: dispatch" do
  it "boxed container read at" do
    result = ze0(<<~'RUBY')
      # Array#at is Array#[] for one integer, and a container read through a boxed
      # slot must reach it (#3821). A nested hash with Integer keys reads through
      # the same boxed path (#3822).
      h = { "a" => [7, 8, 9] }
      p h["a"].at(0)
      p h["a"].at(-1)
      p h["a"][1]
      p [1, 2, 3].at(1)
      xs = [4, 5]
      p xs.at(0)

      q = { "a" => { 1 => "x", 2 => "y" } }
      p q["a"][1]
      p q["a"][9]
      r = { "a" => { 1 => 10 } }
      p r["a"][1]
      s = { "a" => { :k => "v" } }
      p s["a"][:k]
    RUBY

    _(result).must_answer <<~'OUT'
      7
      9
      8
      2
      4
      "x"
      nil
      10
      "v"
    OUT
  end

  it "empty hash poly keys" do
    result = ze0(<<~'RUBY')
      # keys/values on an evidence-free empty {} (stays poly) and on a hash read out
      # of a poly slot. Previously rejected ("unsupported call keys recv=...ty39").
      def id(x) = x

      # empty hash literal in a local: keys/values are empty arrays
      x = {}
      p x.keys
      p x.values
      p x.empty?
      p x.size

      # never-populated empty-hash ivar: keys/values still resolve
      class Store
        def initialize; @h = {}; end
        def ks; @h.keys; end
        def vs; @h.values; end
      end
      s = Store.new
      p s.ks
      p s.vs

      # a populated heterogeneous hash boxed through poly still answers keys/values
      h = {1 => 2, "a" => 3}
      p h.keys
      p h.values

      # symbol-keyed poly hash
      g = {a: 1, b: "x"}
      p g.keys
      p g.values

      # an empty hash that later gets writes is unaffected (refines as before)
      m = {}
      m[1] = 10
      m[2] = 20
      p m
    RUBY

    _(result).must_answer <<~'OUT'
      []
      []
      true
      0
      []
      []
      [1, "a"]
      [2, 3]
      [:a, :b]
      [1, "x"]
      {1 => 10, 2 => 20}
    OUT
  end

  it "merge with a keyword, dup and fetch each resolve on the hash variant that carries them" do
    result = ze0(<<~'RUBY')
      # #551. Three additional Hash dispatch cells the prior #510 /
      # #546 work hadn't covered: sym_poly_hash#merge(kwarg) /
      # str_int_hash#dup / str_poly_hash#fetch. Each one was
      # producing a `cannot resolve call to 'X' on <hash_variant>
      # (emitting 0)` warning and silently returning 0; this drove
      # silent-wrong rendering in Sam's roundhouse blog
      # (ActionView's link_to / button_to / content_for_get).

      def merge_kwarg(h); h.merge(c: 3); end
      m = merge_kwarg({ a: 1, b: "two" })
      puts m.length
      puts m.has_key?(:a)
      puts m.has_key?(:c)

      def dup_strint(h); h.dup; end
      d = dup_strint({ "a" => 1, "b" => 2 })
      puts d.length
      puts d["a"]
      puts d["b"]

      def fetch_strpoly(h, k); h.fetch(k, "miss"); end
      hp = { "a" => 1, :b => "two" }
      puts fetch_strpoly(hp, "a")
      puts fetch_strpoly(hp, "missing")
    RUBY

    _(result).must_answer <<~'OUT'
      3
      true
      true
      2
      1
      2
      1
      miss
    OUT
  end

  it "a Float value survives a read by key, with its fractional part" do
    result = ze0(<<~'RUBY')
      # Float values stored in a Hash must survive a read by key. Before, a
      # float-valued hash literal had no dedicated typed variant and fell
      # through to the str_int_hash default, truncating the fractional part
      # on read (52.9 -> 52). Float values now route to poly storage so each
      # slot keeps its own tag.

      # String key, float value
      h = { "k" => 52.9 }
      puts h["k"]

      # Symbol key, float value
      hs = { a: 1.5, b: 2.5 }
      puts hs[:b]

      # Integer key, float value
      hi = { 0 => 1.5, 1 => 2.5 }
      puts hi[1]

      # Built then mutated keeps the fraction
      hb = { "pi" => 3.14 }
      hb["e"] = 2.71
      puts hb["pi"]
      puts hb["e"]

      # Control: an int-valued hash is unaffected
      hint = { "x" => 7 }
      puts hint["x"]
    RUBY

    _(result).must_answer <<~'OUT'
      52.9
      2.5
      2.5
      3.14
      2.71
      7
    OUT
  end

  it "merge reads the argument as the variant it really is, not as the receiver's layout" do
    result = ze0(<<~'RUBY')
      # `{ sym: v }.merge(opts)` where opts only reads poly: the argument holds
      # whichever hash variant the value really is, so casting it to the receiver's
      # layout read one struct through another -- a Symbol key was then dereferenced
      # as a char * (#3975).
      module VH
        def self.render(attrs)
          out = +""
          attrs.each { |k, v| out << " #{k}=#{v}" }
          out
        end

        def self.sheet(href, opts) = render({ rel: "stylesheet", href: href }.merge(opts))
        def self.button(opts)      = render({ type: "submit" }.merge(opts))
        def self.form(href, opts)  = render({ action: href, method: "post" }.merge(opts))
        def self.raw(attrs)        = render(attrs)
      end

      p VH.sheet("app.css", {})
      p VH.button({ "class" => "btn" })
      p VH.form("/x", { id: "f" })
      p VH.raw({ "data-id" => "7" })

      # a Hash#default(key) whose key type cannot be one of this hash's keys answers
      # the plain default rather than handing the wrong pointer to the default proc
      p Hash.new(5).default(4)
      p({}.default(4))
      p({}.default)
      d = Hash.new { |h, k| "made-#{k}" }
      p d.default("x")
      p d.default
    RUBY

    _(result).must_answer <<~'OUT'
      " rel=stylesheet href=app.css"
      " type=submit class=btn"
      " action=/x method=post id=f"
      " data-id=7"
      5
      nil
      nil
      "made-x"
      nil
    OUT
  end

  it "a lookup whose key arrives boxed checks the tag before it reads the union" do
    result = ze0(<<~'RUBY')
      # A hash lookup whose key arrives boxed must check the tag before reading the
      # union member: the same call site reached with a String and with a Float read
      # the Float's bits as a pointer (#3810).
      NAMED = { 'red' => '#FF0000' }.freeze
      def named?(v)
        NAMED.key?(v)
      end
      def fetch_it(v)
        NAMED[v]
      end
      p named?('red')
      p named?(0.5)
      p named?(:red)
      p fetch_it('red')
      p fetch_it(2)

      SYMS = { a: 1 }
      def sym_key?(v)
        SYMS.key?(v)
      end
      p sym_key?(:a)
      p sym_key?('a')
      p sym_key?(3.5)

      INTS = { 7 => 'seven' }
      def int_key?(v)
        INTS.key?(v)
      end
      p int_key?(7)
      p int_key?('x')
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      false
      "#FF0000"
      nil
      true
      false
      false
      true
      false
    OUT
  end

  it "a value read out of a mixed hash into a local keeps its own runtime type" do
    result = ze0(<<~'RUBY')
      h = {"int" => -9}
      h["array"] = [1, 2]
      h["bool"] = false
      h["float"] = 1.5
      h["hash"] = {"nested" => 7}
      h["nil"] = nil
      h["string"] = "text"

      h.keys.sort.each do |key|
        value = h[key]
        rendered = if value.is_a?(Array)
          "array:" + value.length.to_s
        elsif value.is_a?(Float)
          "float:" + value.to_s
        elsif value.is_a?(Integer)
          "int:" + value.abs.to_s
        elsif value.is_a?(String)
          "string:" + value.upcase
        elsif value.is_a?(Hash)
          "hash"
        elsif value.nil?
          "nil"
        else
          "bool:" + value.to_s
        end
        puts key + "=" + rendered
      end
    RUBY

    _(result).must_answer <<~'OUT'
      array=array:2
      bool=bool:false
      float=float:1.5
      hash=hash
      int=int:9
      nil=nil
      string=string:TEXT
    OUT
  end

  it "nil hash param boxed as nil" do
    result = ze0(<<~'RUBY')
      # A hash-typed slot holding nil is a NULL pointer, and boxing it into a poly
      # wrapped that NULL in a truthy SP_TAG_OBJ instead of answering nil. So
      # `h.nil?` was false for a hash that WAS nil, `unless h` fell through, and the
      # first read of it dereferenced NULL -- a segfault with a silent-corruption
      # stage in front of it. (matz/spinel#4134, reduced from #4132)
      #
      # What makes the slot nil is an omitted optional parameter, which is why an
      # explicit `nil` at the same call site behaved differently from omitting it:
      # both paths have to box the same NULL.
      class Req
        def initialize(method, path, initheader = nil)
          @method = method
          @path = path
          @headers = {}
          unless initheader.nil?
            initheader.each { |k, v| @headers[k.to_s.downcase] = v.to_s }
          end
        end
        def path = @path
        def [](n) = @headers[n.to_s.downcase]
        def header_nil? = @headers.empty?
      end

      class Post < Req
        def initialize(path, initheader = nil)
          super("POST", path, initheader)
        end
      end

      # The omitted form and the hash form in one program: the second call site is
      # what gives the parameter a hash type, and the first is what puts NULL in it.
      a = Post.new("/f")
      b = Post.new("/a", { "content-type" => "text/plain" })
      p a.path
      p b.path
      p b["content-type"]
      p a["content-type"]
      p a.header_nil?
      p b.header_nil?

      # Passing the default explicitly has to agree with omitting it.
      c = Post.new("/x", nil)
      p c.path
      p c["content-type"]
      p c.header_nil?

      # The predicate itself, on a nil hash reaching a poly parameter.
      def peek(h)
        return "nil" if h.nil?
        "hash:#{h.size}"
      end
      p peek(nil)
      p peek({ "a" => "1" })

      # A nil hash in an array, which boxes through the same path.
      box = [nil, { "k" => "v" }]
      p box[0].nil?
      p box[1].nil?
      p box[1]["k"]
    RUBY

    _(result).must_answer <<~'OUT'
      "/f"
      "/a"
      "text/plain"
      nil
      true
      false
      "/x"
      nil
      true
      "nil"
      "hash:1"
      true
      false
      "v"
    OUT
  end

  it "nullable poly hash arg unbox" do
    result = ze0(<<~'RUBY')
      # When a `sym_poly_hash?` (or `str_poly_hash?`) survives a nil-
      # guard and its `[]` value flows into a typed-param call site,
      # analyze's cached infer for `recv[k]` falls through to int
      # (the leaf-type dispatch rejects the `?`-suffixed recv name), so
      # downstream the call site sees `at == "int"` and skips the
      # poly→int unbox. The actual C emit is sp_<*PolyHash>_get(...)
      # returning sp_RbVal — the call then passes sp_RbVal into a
      # mrb_int slot.
      #
      # Codegen-side fix: expr_emits_poly_rb_val recognizes the shape
      # at emit time (independent of analyze cache) and the unbox
      # fires in compile_expr_for_expected_type and the poly-dispatch
      # arm.
      #
      # Real repro lives in roundhouse spinel-blog main.rb:
      #   matched = Router.match(...)
      #   return if matched.nil?           # matched still : sym_poly_hash?
      #   controller = Main.instantiate_controller(matched[:controller])
      #   controller.process_action(matched[:action])
      # Both `instantiate_controller` (Symbol param) and the poly
      # dispatch of `process_action` (Symbol param) caught the bug.

      module Counter
        def self.double(n)
          n * 2
        end
      end

      class A
        def act(n)
          n + 100
        end
      end

      class B
        def act(n)
          n + 200
        end
      end

      def fetch(present)
        if present
          { value: 21, label: "x" }
        else
          nil
        end
      end

      def pick(flag)
        if flag
          A.new
        else
          B.new
        end
      end

      m = fetch(true)
      if m.nil?
        puts "missing"
      else
        # Module class method dispatch — exercises
        # compile_expr_for_expected_type via
        # compile_constant_recv_expr → compile_call_args_with_defaults.
        puts Counter.double(m[:value])
        # Polymorphic-receiver dispatch arm — exercises
        # compile_poly_method_call's arm-arg unbox.
        puts pick(true).act(m[:value])
        puts pick(false).act(m[:value])
      end

      # Same shape with str_poly_hash?.
      def fetch_str(present)
        if present
          { "k1" => 7, "k2" => "v" }
        else
          nil
        end
      end

      s = fetch_str(true)
      if s.nil?
        puts "missing"
      else
        puts Counter.double(s["k1"])
      end
    RUBY

    _(result).must_answer <<~'OUT'
      42
      121
      221
      14
    OUT
  end

  it "poly arg int keyed hash" do
    result = ze0(<<~'RUBY')
      # `if status.is_a?(Integer)` inside a method where status is
      # poly-typed (the method's caller-union widened it). The then-arm
      # uses status as the key into an Int-keyed hash. Pre-fix the
      # IntStrHash dispatch (`[]`, has_key?, fetch) compiled the key
      # arg via compile_arg0 / compile_expr without unboxing the poly
      # value, and the C call passed sp_RbVal to a mrb_int param,
      # tripping the C compile with int-from-pointer.
      #
      # IntStrHash's three key-receiving arms now route through
      # compile_arg0_as_int (or explicit `.v.i` unbox in fetch), which
      # detects a poly arg and emits `(arg).v.i`. At runtime the is_a?
      # guard ensures the tag is SP_TAG_INT so the unbox reads the
      # intended integer value; with no guard the unbox would still
      # compile but look up a meaningless key (no crash — union
      # type-pun is defined, just non-meaningful).
      #
      # The broader is_a? narrowing for other Int-context use sites
      # (method call args expecting mrb_int, arithmetic ops, etc.)
      # remains a separate concern.

      def lookup(status)
        table = { 200 => "OK", 404 => "NotFound" }
        if status.is_a?(Integer)
          return table.fetch(status, "x")
        end
        "no"
      end

      puts lookup(200)
      puts lookup(404)
      puts lookup("nope")

      def has_status?(status)
        table = { 200 => "OK" }
        if status.is_a?(Integer)
          return table.has_key?(status)
        end
        false
      end

      puts has_status?(200)
      puts has_status?("nope")
    RUBY

    _(result).must_answer <<~'OUT'
      OK
      NotFound
      no
      true
      false
    OUT
  end

  it "poly dispatch hash param variant" do
    result = ze0(<<~'RUBY')
      # Two classes defining the same method with a Hash parameter, called on a
      # receiver whose type is the union of both. A parameter already typed as a
      # concrete hash by its callers was being NARROWED from the method body's own
      # writes -- str->poly down to str->str -- which converts nothing: it
      # reinterprets the caller's sp_StrPolyHash * through an sp_StrStrHash *
      # parameter. The two arms of the dispatch then disagreed on the variant, the
      # call passed the wrong struct, and the program hung.
      class Leaf
        def initialize(char) = @char = char
        def walk(table) = table[@char] = "x"
      end

      class Branch
        def initialize(kid) = @kid = kid
        def walk(table) = @kid.walk(table)
      end

      nodes = [Leaf.new("a")]
      nodes << Branch.new(Leaf.new("b"))
      tree = nodes.last

      table = {}
      tree.walk(table)
      p table["b"].length
      p table.size

      # both arms reached from the same site, mutating the caller's hash in place
      shared = {}
      nodes.each { |n| n.walk(shared) }
      p shared.keys.sort
      p shared["a"]
      p shared["b"]

      # ... and read back with a key that comes from ANOTHER hash's iteration, which
      # is what made the caller's `{}` and the callee's parameter name different C
      # structs: the key context narrowed the literal while the callee, invisible to
      # it, filled the hash with its own key type (#3386).
      freqs = { "a" => 5, "b" => 9 }
      tally = {}
      nodes.each { |n| n.walk(tally) }
      p freqs.sum { |ch, f| f * tally[ch].length }
      p freqs.map { |ch, _| tally[ch] }.sort
    RUBY

    _(result).must_answer <<~'OUT'
      1
      1
      ["a", "b"]
      "x"
      "x"
      14
      ["x", "x"]
    OUT
  end

  it "poly hash fetch dispatch" do
    result = ze0(<<~'RUBY')
      # A Hash reached through a poly value must dispatch `fetch` to its storage the
      # same way `[]` does. The PR added poly `[]` arms but left `fetch` arm-less, so
      # `fetch(present_key)` on a poly-valued hash fell through to the seeded default
      # (or dropped its value as nil) even when the key existed. Cover fetch-present,
      # fetch-with-default (absent), fetch-raising KeyError (absent), and a poly key.
      class Sel
        def [](i); i * 10; end          # a user `[]` forces per-class poly dispatch
        def fetch(i); i * 100; end      # a user `fetch` too
      end
      class Holder
        def initialize(real)
          h = {}
          h["a"] = 1
          h[2]   = "b"                  # heterogeneous keys -> PolyPolyHash
          @map = real ? h : "none"      # poly-valued ivar (widens the Hash to poly)
        end
        def fetch_present(name); @map.fetch(name); end          # string key, present
        def fetch_default(name); @map.fetch(name, -1); end       # string key, absent
        def poly_key(name); @map.fetch(name.length > 9 ? nil : name); end  # poly key
      end
      h = Holder.new(true)
      puts "present: #{h.fetch_present("a")}"
      puts "default: #{h.fetch_default("zz")}"
      puts "poly key: #{h.poly_key("a")}"
      begin
        h.fetch_present("nope")
        puts "no raise (BUG)"
      rescue KeyError
        puts "KeyError"
      end
      # the user-class arms still win when the poly value is really a Sel
      puts "user fetch: #{Sel.new.fetch(3)}"
    RUBY

    _(result).must_answer <<~'OUT'
      present: 1
      default: -1
      poly key: 1
      KeyError
      user fetch: 300
    OUT
  end

  it "poly hash fetch with default" do
    result = ze0(<<~'RUBY')
      # fetch(key, default) on a poly value that is actually a string-keyed hash
      # (here the nested hash reached via the outer hash's own fetch) must perform
      # the lookup, not collapse to the default. The poly-dispatch guard previously
      # admitted only `[]`/include?-family calls, so a `fetch` with no user candidate
      # was dropped and returned an empty string.
      def pick(params)
        raw_sub = params.fetch "article", {}
        sub = if raw_sub.is_a?(Hash)
          raw_sub
        else
          {}
        end
        title = sub.fetch "title", "MISSING"
        body  = sub.fetch "body", "MISSING"
        "#{title}/#{body}"
      end

      puts pick({ "article" => { "title" => "hello", "body" => "world" } })
      puts pick({ "article" => { "title" => "only" } })
      puts pick({ "other" => { "x" => "y" } })
    RUBY

    _(result).must_answer <<~'OUT'
      hello/world
      only/MISSING
      MISSING/MISSING
    OUT
  end

  it "poly hash index dispatch" do
    result = ze0(<<~'RUBY')
      # A string-keyed Hash held in a poly value and indexed by `[]` with a poly key
      # (a key whose static type is not narrowed to String) must reach the hash
      # storage even when a user class defines `[]` (routing `[]` through the
      # per-class poly dispatch). Without hash arms there the lookup returned nil --
      # doom's `@textures[anim_texture(name)]` (a StrPolyHash arriving as a poly
      # value, poly key) resolved to nil so walls drew untextured.
      class Sel
        def [](i); i * 10; end   # a user `[]` forces per-class poly dispatch
      end
      class Holder
        def initialize(real)
          h = {}
          h["a"] = [1, 1]   # poly (array) values -> StrPolyHash
          h["b"] = [2, 2]
          @map = real ? h : "none"        # poly-valued ivar
        end
        def kk(n); n.length > 3 ? nil : n; end   # returns String|nil -> a poly key
        def get(name); @map[kk(name)]; end
      end
      h = Holder.new(true)
      p h.get("a")
      p h.get("b")
      p h.get("zz")
      puts Sel.new[4]
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 1]
      [2, 2]
      nil
      40
    OUT
  end

  it "poly hash inspect" do
    result = ze0(<<~'RUBY')
      # A hash arriving as a poly value (nested, kwargs-splat, Marshal round-trip)
      # must inspect through its hash-variant inspect helper, not as #<Object>.

      # Nested hash literal: the inner hash is boxed as a poly value.
      p({a: {b: 1}})

      # Double-splat keyword capture returns a symbol-keyed hash.
      def f(**k) = k
      p f(x: 1)

      # Rest + keyword splat: the hash rides inside a poly array.
      def g(*a, **k) = [a, k]
      p g(1, x: 2)

      # Marshal round-trip builds a poly-poly hash at runtime.
      p Marshal.load(Marshal.dump({a: 1, b: 2}))

      # Route a hash receiver through a method param so the call is not
      # constant-folded; the value is an opaque poly hash at the inspect site.
      def show(h) = p(h)
      show({k: {v: [1, 2]}, w: 3})

      # String-keyed hashes (str_int_hash / str_str_hash) whose cls_id block sits
      # next to Exception: arriving as poly values they must still dispatch to the
      # hash inspect path, not the Exception path.
      def wrap(h) = {outer: h}
      p wrap({"a" => 1, "b" => 2})
      p wrap({"k" => "v"})
    RUBY

    _(result).must_answer <<~'OUT'
      {a: {b: 1}}
      {x: 1}
      [[1], {x: 2}]
      {a: 1, b: 2}
      {k: {v: [1, 2]}, w: 3}
      {outer: {"a" => 1, "b" => 2}}
      {outer: {"k" => "v"}}
    OUT
  end

  it "poly hash with range" do
    result = ze0(<<~'RUBY')
      # Range crossing into a poly container: a hash literal mixing
      # Integer values with Range values used to fall through
      # `box_non_nullable_value_to_poly`'s default branch and emit
      # `sp_box_int(sp_range_new(...))`, which the C compiler rejects
      # (sp_Range is 16 bytes; sp_RbVal's union is 8). Same shape for
      # heterogeneous poly arrays.
      #
      # Fix: heap-allocate the Range and box the pointer through a new
      # SP_BUILTIN_RANGE cls_id (sp_box_range copies the stack range
      # onto the GC heap before returning the boxed sp_RbVal).

      # Hash form (the canonical Rails strong-status shape from the issue).
      STATUS_SYMBOLS = {
        success:    200..299,
        redirect:   300..399,
        missing:    404,
        not_found:  404,
        error:      500..599,
        ok:         200,
        created:    201,
        no_content: 204,
      }

      puts STATUS_SYMBOLS[:success]    # 200..299
      puts STATUS_SYMBOLS[:ok]         # 200
      puts STATUS_SYMBOLS[:created]    # 201
      puts STATUS_SYMBOLS[:error]      # 500..599
      puts STATUS_SYMBOLS[:not_found]  # 404

      # Array form — same fundamental issue (Range crosses into poly slot).
      arr = [200..299, 200, 300..399, 404]
      puts arr.length                  # 4
      puts arr[0]                      # 200..299
      puts arr[1]                      # 200
      puts arr[2]                      # 300..399
      puts arr[3]                      # 404
    RUBY

    _(result).must_answer <<~'OUT'
      200..299
      200
      201
      500..599
      404
      4
      200..299
      200
      300..399
      404
    OUT
  end

  it "poly idx int nullable" do
    result = ze0(<<~'RUBY')
      # A poly-typed receiver indexed by an int? value (from a shipped int_int_hash
      # lookup) must dispatch correctly. Before the codegen index-parity fix,
      # emit_poly_builtin_dispatch / compile_poly_method_call skipped every arm when
      # the index type was int? (not int), collapsing the result to nil. This repro
      # needs NO int-array []->int? flip: the int? comes purely from int_int_hash#[].

      h = { 0 => 2, 1 => 3 }   # int_int_hash; #[] returns int?
      k = h[0]                  # int? (value 2)

      # A heterogeneous literal makes `box` a poly_array; its element read is `poly`.
      box = [[10, 20, 30, 40, 50], "tail"]
      tbl = box[0]              # poly receiver (an int_array at runtime)

      p tbl[k]                  # poly recv [] with int? index -> want 30
    RUBY

    _(result).must_answer "30\n"
  end

  it "poly keyed hash pipeline" do
    result = ze0(<<~'RUBY')
      # Heterogeneous-key Hash through the full reassign-and-store pipeline.
      # Mirrors optcarrot's CPU#add_mappings(addr, peek, poke):
      #   peek = @peeks[peek] ||= peek
      # where peek can be either a Method or a non-Method object — the param
      # slot widens to poly so the `||=` lookup result flows back into the
      # same local without unboxing.

      class Pipeline
        def initialize
          @peeks = {}
          @stored = []
        end
        # `item` widens to poly across the call sites below (Method,
        # IntArray) so the param is sp_RbVal — the dedup reassignment
        # `item = @peeks[item] ||= item` works without re-typing the slot.
        def add(item)
          item = @peeks[item] ||= item
          @stored.push(item)
        end
        def cache_size
          @peeks.size
        end
        def stored_count
          @stored.length
        end
      end

      class Source
        def self.read; 42; end
      end

      p = Pipeline.new
      m = Source.method(:read)
      arr = [1, 2, 3]
      p.add(m)              # cache: {m => m}
      p.add(arr)            # cache: {m => m, arr => arr}
      p.add(Source.method(:read))   # eql? to m → cache stays size 2
      p.add(arr)            # identity hit → size still 2
      puts p.cache_size     # 2
      puts p.stored_count   # 4 (every call appends)
    RUBY

    _(result).must_answer "2\n4\n"
  end

  it "poly length on scalar hash" do
    result = ze0(<<~'RUBY')
      # A `params = {}` filled with a computed String key is a StrStrHash. Once any
      # user class defines #length, `params.length` goes through poly dispatch instead
      # of the monomorphic builtin -- the dispatch switch was missing the scalar-valued
      # hash arms (StrStr/StrInt/IntStr) and returned the seed 0. #inspect/#[] stayed
      # correct because they never go poly. (#1614)
      module App
        def self.build_params(pattern, path)
          pattern_parts = pattern.split("/")
          path_parts    = path.split("/")
          params = {}
          i = 0
          while i < pattern_parts.length
            pp = pattern_parts[i]
            ap = path_parts[i]
            params[pp[1..]] = ap if pp.start_with?(":")
            i += 1
          end
          params
        end
        # An unrelated user #length anywhere forces `.length` to poly-dispatch.
        class Flash
          def length; 99; end
        end
      end

      h = App.build_params("/articles/:id/comments/:cid", "/articles/7/comments/3")
      puts "k0=#{h.keys[0]} k1=#{h.keys[1]}"
      puts h["id"]
      puts "length=#{h.length}"
      puts "size=#{h.size}"
      puts "empty=#{h.empty?}"

      empty = App.build_params("/static", "/static")
      puts "empty_len=#{empty.length}"
      puts "empty_empty=#{empty.empty?}"
    RUBY

    _(result).must_answer <<~'OUT'
      k0=id k1=cid
      7
      length=2
      size=2
      empty=false
      empty_len=0
      empty_empty=true
    OUT
  end

  it "poly poly hash each value" do
    result = ze0(<<~'RUBY')
      # `Hash#each_value { |v| ... }` for poly_poly_hash. The previous
      # dispatch only knew about `each` / `each_pair`; `each_value` fell
      # through to the unresolved-call warning and silently dropped the
      # block body.
      #
      # Surfaced via optcarrot's PPU init
      # `entries.each_value {|a| a.uniq! {|entry| entry.object_id } }`
      # where `entries` is a heterogeneous-key heterogeneous-value hash.

      h = {}
      h[[1, 2]] = "ab"
      h[[3, 4]] = "cd"
      h["s"] = 99
      h[5] = [10, 20]

      # Each value passed to the block in insertion order; key ignored.
      h.each_value do |v|
        puts v.to_s
      end
      puts "---"

      # Mutating the block's local doesn't affect the hash.
      h.each_value do |v|
        v = "ignored"
        puts v
      end
      puts "---"

      # No block param: still iterates (counts side-effecting expr).
      i = 0
      h.each_value do
        i = i + 1
      end
      puts i
    RUBY

    _(result).must_answer <<~'OUT'
      ab
      cd
      99
      [10, 20]
      ---
      ignored
      ignored
      ignored
      ignored
      ---
      4
    OUT
  end

  it "poly poly hash fetch dup" do
    result = ze0(<<~'RUBY')
      # #560 (Sam Ruby). poly_poly_hash variant gained fetch + dup
      # dispatch arms (mirror of #551's str_poly_hash / sym_poly_hash
      # work). When two writers to the same ivar use keys of
      # incompatible inferred types (int-defaulted param + sym
      # literal), spinel widens the storage to poly_poly_hash; the
      # read side then needs the dispatch cells to lower correctly.

      module M
        @h = {}

        def self.write1(k, v)
          @h[k] = v
        end

        def self.write2(v)
          @h[:special] = v
        end

        def self.read(k)
          @h.fetch(k, nil)
        end
      end

      M.write2("hello")
      puts M.read(:special)
      puts M.read(:missing).nil?
    RUBY

    _(result).must_answer "hello\ntrue\n"
  end

  it "poly recv aset poly key" do
    result = ze0(<<~'RUBY')
      # #464: `merged[k] = v` where merged is poly-recv AND k is also
      # poly. Pre-fix, the poly recv `[]=` dispatcher emitted only
      # Array setter arms which expect mrb_int index, so passing
      # sp_RbVal as the index argument failed C compile.
      #
      # Fix: when idx is poly, dispatch by both recv cls_id AND
      # key tag at runtime.

      def get_poly(h, key)
        h[key]
      end

      def write_back(merged, k, v)
        merged[k] = v
      end

      def run(outer)
        merged = get_poly(outer, "m")
        # k and v as poly via a helper that lets analysis lose their
        # concrete type. wrap_key boxes a string into sp_RbVal via
        # the poly_hash leaf.
        pairs = get_poly(outer, "pairs")
        k = get_poly(pairs, "k")
        v = get_poly(pairs, "v")
        write_back(merged, k, v)
        merged["b"]
      end

      outer = { "m" => { "a" => 1 }, "pairs" => { "k" => "b", "v" => 99 } }
      puts run(outer)
    RUBY

    _(result).must_answer "99\n"
  end

  it "poly recv fetch arm incompat" do
    result = ze0(<<~'RUBY')
      # Sibling to poly_recv_fetch_hash_arms.rb. The dispatch arm for a
      # user class whose `fetch` is sym-keyed (pinned by sym-only direct
      # callers) should be SUPPRESSED at the dispatch site when the source
      # call passes a String key — the String can't be cast to mrb_int sym,
      # and at runtime the receiver in any source-level-valid path is a
      # Hash, never the user class.
      #
      # Pre-fix: spinel emitted the FlashLike arm with String args going
      # into a mrb_int slot — fails C compile.
      # Post-fix: arm suppressed; Hash arms (added in the parent fix) cover
      # the actual runtime path.

      class FlashLike
        def fetch(key, default)
          @last = key
          default
        end
      end

      # Sym-only direct callers commit FlashLike#fetch's `key` to sym
      # (mrb_int) in isolation. The dispatch site below mustn't widen it.
      def warmup
        f = FlashLike.new
        f.fetch(:a, "1")
        f.fetch(:b, "2")
      end

      warmup

      def get_raw(h); h["x"]; end

      def lookup(h)
        sub = get_raw(h)
        sub.fetch("title", "")
      end

      puts lookup({ "x" => { "title" => "real" } })
    RUBY

    _(result).must_answer "real\n"
  end

  it "poly recv fetch hash arms" do
    result = ze0(<<~'RUBY')
      # #470: `sub.fetch(k, d)` where sub is sp_RbVal (came from a
      # StrPolyHash lookup). Pre-fix the poly-recv `.fetch` dispatch
      # enumerated only user-class arms (any class with `def fetch`)
      # and silently returned the default for any Hash-storage receiver
      # at runtime. Sibling to #456, which added Hash arms to poly-recv
      # `[]` / `[]=` but not to `fetch`.
      #
      # A user-defined class with a `fetch` method is needed to force
      # the call site through the polymorphic dispatch (which is what
      # missed the Hash arms); without it the call site never picks the
      # poly path because no arm contributes.

      class FlashLike
        def fetch(key, default)
          "from-flash"
        end
      end

      # Keep FlashLike#fetch alive so the user-class arm is emitted.
      puts FlashLike.new.fetch("x", "y")

      def get_raw(h)
        h["x"]
      end

      def lookup(h)
        sub = get_raw(h)
        sub.fetch("title", "DEFAULT")
      end

      puts lookup({ "x" => { "title" => "real" } })
    RUBY

    _(result).must_answer "from-flash\nreal\n"
  end

  it "poly recv hash dup" do
    result = ze0(<<~'RUBY')
      # Poly-recv hash `.dup`: the call `outer[k].dup` where outer is
      # a `*_poly_hash` (and so `outer[k]` returns sp_RbVal) used to
      # fall through to int-default ("cannot resolve call to 'dup' on
      # int") and silently no-op. Downstream `iv = local` writes
      # against typed-hash slots then failed -Wint-conversion.
      #
      # Two-sided fix:
      #  - analyze: infer_call_type for `.dup` recognizes the
      #    `nullable_poly_hash[k].dup` shape and returns poly so the
      #    receiving LV slot is typed sp_RbVal up front.
      #  - codegen: emit_poly_builtin_dispatch grew a `dup` arm that
      #    dispatches by cls_id through the matching sp_*Hash_dup
      #    runtime helper, boxing the result back as obj.
      #
      # Surfaces in real-blog's `merged = matched[:path_params].dup`
      # in Main.run — 8 cascading warnings (lv_merged stays int, all
      # downstream `iv_params = lv_merged` stores warn).

      module Router
        def self.match(present)
          if present
            return { controller: :a, path_params: { "id" => "7" } }
          end
          nil
        end
      end

      # Sink consuming a poly-typed hash. Widens the param to
      # sp_RbVal up front via the literal-init call below.
      def first_value(h)
        h["id"]
      end

      # Pin first_value's `h` param to poly via a direct poly-call
      # site. This is a workaround for the LV-widening gap: without
      # it the param defaults to int because the only call site is
      # downstream of the .dup widening.
      def make_poly_hash
        hh = { "id" => "fallback" }
        m = Router.match(true)
        if m
          return m[:path_params].dup
        end
        hh
      end

      x = make_poly_hash
      puts first_value(x)
    RUBY

    _(result).must_answer "7\n"
  end

  it "poly recv hash each dispatch" do
    result = ze0(<<~'RUBY')
      # Hash#each on a poly-typed receiver (sp_RbVal) was silently
      # iterating zero times: compile_each_block's `rt == "poly"` arm
      # emitted a cls_id-keyed length / per-iteration table covering
      # Range and the six Array variants but no Hash variants. The
      # loop's `_t2_len` defaulted to 0 and the block never ran.
      #
      # Fix: codegen `scan_for_container_typedef_usage` arms every
      # Hash typedef when any `recv.each { ... }` is present
      # (conservative -- the recv may resolve to poly at the use site
      # even when the static analyzer's first pass sees a narrower
      # type), and the poly-each emit pass now includes 8 hash arms:
      # `_t2_len` reads `h->len`, the per-iteration value packs the
      # (key, value) as a 2-element PolyArray so the existing
      # block-param splat delivers `|k, v|`. Issue #603.

      module M
        def self.iter(hash)
          n = 0
          hash.each { |_k, _v| n += 1 }
          n
        end
      end

      # Two heterogeneous call sites force the param to sp_RbVal so
      # the poly-each emit path is exercised on both shapes.
      puts "a=#{M.iter({ a: 1, b: 2 })}"     # sym_int_hash, expect 2
      puts "b=#{M.iter({ "x" => "y" })}"     # str_str_hash, expect 1

      # Same surface with int-keyed hash + str values, an empty hash,
      # and a single-pair str_int_hash. The third call drives the
      # per-iteration block param so we verify keys/values arrive.
      def m3(h)
        out = ""
        h.each { |k, v| out += k.to_s + "=" + v.to_s + ";" }
        out
      end

      puts m3({1 => "one", 2 => "two"})        # int_str_hash
      puts m3({})                              # empty
      puts m3({"k" => 42})                     # str_int_hash
    RUBY

    _(result).must_answer <<~'OUT'
      a=2
      b=1
      1=one;2=two;

      k=42;
    OUT
  end

  it "poly recv range sym hash dispatch" do
    result = ze0(<<~'RUBY')
      # Two fixes for poly-receiver dispatch on built-in container types
      # from issues #588 and #590.
      #
      # #588: `case x; when Range; r.include?(x); end` -- the poly-recv
      # include? dispatch enumerated IntArray / IntStrHash cls_ids but
      # missed SP_BUILTIN_RANGE, so a Range narrowed via case/when fell
      # through to the default `0` (always-false). `sp_range_include` was
      # added in lib/sp_runtime.h and the codegen dispatch arm picks it
      # up.
      #
      # #590: A sym_*_hash lookup with a poly-typed key (e.g. an
      # `is_a?(Symbol)`-narrowed local that still carries sp_RbVal at C
      # level) emitted `sp_SymPolyHash_get(h, lv_x)` where the parameter
      # expects `sp_sym`. The `compile_arg0_as_sym` helper now extracts
      # `.v.i` for poly args; the sym_int_hash / sym_str_hash arms also
      # reuse it, and the prior "non-symbol key -> fallback default"
      # fast-path no longer fires for poly args (those CAN be symbols at
      # runtime).
      #
      # Also extends `sp_poly_inspect` to dispatch built-in container
      # cls_ids (Range, Time, typed Arrays) instead of returning the bare
      # "#<Object>" placeholder -- the #590 minimal repro stored a Range
      # inside a sym_poly_hash, and `result.inspect` printed "#<Object>"
      # instead of "200..299".

      # --- #588: case/when narrowing to Range, include? via poly recv.
      def check_range(value, actual)
        case value
        when Range
          value.include?(actual)
        when Integer
          value == actual
        else
          false
        end
      end

      puts check_range(200..299, 200)   # true
      puts check_range(200..299, 300)   # false
      puts check_range(200..299, 250)   # true
      puts check_range(404, 404)        # true
      puts check_range(404, 200)        # false

      # --- #590: sym-keyed hash with poly-typed key extracted from a
      # Symbol|Integer narrowing.
      H = { a: 200..299, b: 404, c: 500 }

      def lookup(expected)
        expected.is_a?(Symbol) ? H[expected] : expected
      end

      puts lookup(:a).inspect           # 200..299  (was "#<Object>" pre-fix)
      puts lookup(:b).inspect           # 404
      puts lookup(:c).inspect           # 500
      puts lookup(503).inspect          # 503
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      true
      true
      false
      200..299
      404
      500
      503
    OUT
  end

  it "sym poly hash merge" do
    result = ze0(<<~'RUBY')
      # `Hash#merge` on a Symbol-keyed hash with heterogeneous values
      # (Symbol => {Integer | String | Boolean | nil}) -- spinel
      # represents this as `sym_poly_hash`. Before this change spinel had
      # no dispatcher for non-mutating `merge` on sym_poly_hash, so the
      # call lowered to an empty hash and every subsequent lookup returned
      # nil.
      #
      # The poly-receiver `[]` arm covers the case where a local's static
      # type was widened to poly (e.g. by an `is_a?` branch) even though
      # the runtime value is a sym_poly_hash. `opt[:k]` then dispatches
      # via the emit_poly_builtin_dispatch helper rather than the typed
      # sym_poly_hash branch above.

      DEFAULTS = { a: 1, b: "two", c: true, d: nil, e: 16 }

      # 1. Non-mutating merge: result has overrides from b, other keys
      #    preserved from a.
      m = DEFAULTS.merge({ a: 99, b: "TWO" })
      puts m[:a]              # 99 (overridden)
      puts m[:b]              # TWO
      puts m[:c]              # true (preserved)
      puts m[:e]              # 16

      # 2. Original receiver is unchanged.
      puts DEFAULTS[:a]       # 1

      # 3. Symbol-key `[]` lookup on a poly-typed local. The is_a?(String)
      #    branch widens `opt`s static type to poly; the merge-result is
      #    boxed back into the same slot. spinel must dispatch the
      #    subsequent `opt[:k]` reads via the poly builtin path.
      def lookup(opt)
        # Mixed-value override hash so spinel infers sym_poly_hash for the
        # `is_a?(String)` boxed branch (and the explicit-Hash call site too).
        opt = { a: 7, c: false } if opt.is_a?(String)
        merged = DEFAULTS.merge(opt)
        return merged[:a], merged[:b], merged[:e]
      end

      a, b, e = lookup("string-input")
      puts a                  # 7  (from the boxed hash inside the if branch)
      puts b                  # two
      puts e                  # 16

      a, b, e = lookup({ a: 100, b: "B", e: 99 })
      puts a                  # 100
      puts b                  # B
      puts e                  # 99
    RUBY

    _(result).must_answer <<~'OUT'
      99
      TWO
      true
      16
      1
      7
      two
      16
      100
      B
      99
    OUT
  end

  it "sym poly hash merge sym int" do
    result = ze0(<<~'RUBY')
      # #559 (Sam Ruby). Sibling of #551. sym_poly_hash.merge with
      # a positional sym_int_hash argument was missing dispatch
      # (only the KeywordHashNode and same-variant shapes were
      # wired). The cross-variant lowering routes through a new
      # sp_SymPolyHash_merge_int runtime helper that boxes each
      # int value as sp_box_int into the result poly slot.

      def f
        h = { a: "x", b: 1 }
        other = { c: 2 }
        h.merge(other)
      end

      m = f
      puts m.length
      puts m.has_key?(:a)
      puts m.has_key?(:b)
      puts m.has_key?(:c)
    RUBY

    _(result).must_answer <<~'OUT'
      3
      true
      true
      true
    OUT
  end
end
