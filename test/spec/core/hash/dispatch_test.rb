# frozen_string_literal: true

require "spec_helper"

describe "Hash: dispatch" do
  it "boxed container read at" do
    result = zr(<<~'RUBY')
      # Array#at is Array#[] for one integer, and a container read out of a hash
      # value must reach it. A nested hash with Integer keys reads the same way.
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
    result = zr(<<~'RUBY')
      # keys/values on an empty {} that nothing writes to, and on a hash read out
      # of a slot whose type is known only at run time.
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
    result = zr(<<~'RUBY')
      # Three Hash calls on three kinds of hash: merge with a keyword
      # argument (Symbol keys, mixed values), dup (String keys, Integer
      # values) and fetch (String keys, mixed values). ActionView's
      # link_to / button_to / content_for_get use these shapes.

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
    result = zr(<<~'RUBY')
      # Float values stored in a Hash must survive a read by key, with the
      # fractional part (52.9 stays 52.9, not 52).

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
    result = zr(<<~'RUBY')
      # `{ sym: v }.merge(opts)` where the type of opts is known only at run time.
      # merge reads the argument as the kind of hash it really is, and its Symbol
      # keys stay Symbols.
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
    result = zr(<<~'RUBY')
      # A hash lookup whose key can be of more than one type: the same call site
      # gets a String and a Float, and each key is compared as what it is.
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
    result = zr(<<~'RUBY')
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
    result = zr(<<~'RUBY')
      # A hash parameter that holds nil is nil: `h.nil?` is true, and `unless h`
      # takes the nil branch.
      #
      # What makes the parameter nil is an omitted optional parameter. An explicit
      # `nil` at the same call site must behave the same as omitting it.
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
    result = zr(<<~'RUBY')
      # A hash with Symbol keys and mixed values, or nil. After a nil
      # guard, a value read with `[]` goes to a method that takes an
      # Integer, and the method gets that Integer.
      #
      # The shape comes from a blog app:
      #   matched = Router.match(...)
      #   return if matched.nil?           # matched is a Hash here
      #   controller = Main.instantiate_controller(matched[:controller])
      #   controller.process_action(matched[:action])
      # It covers a module method call and a call on a receiver that can
      # be of more than one class.

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
        # Module class method call.
        puts Counter.double(m[:value])
        # Call on a receiver that can be an A or a B.
        puts pick(true).act(m[:value])
        puts pick(false).act(m[:value])
      end

      # Same shape with String keys and mixed values, or nil.
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
    result = zr(<<~'RUBY')
      # `if status.is_a?(Integer)` inside a method where status can be of
      # more than one type (the callers pass different types). The
      # then-arm uses status as the key into an Integer-keyed hash, with
      # `[]`, has_key? and fetch. The is_a? guard makes sure the key is
      # an Integer.

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
    result = zr(<<~'RUBY')
      # Two classes defining the same method with a Hash parameter, called on a
      # receiver whose type is the union of both. A parameter already typed as a
      # concrete hash by its callers was being NARROWED from the method body's own
      # writes -- String => mixed down to String => String. Both methods must use
      # the hash that the caller passes, as it is.
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

      # ... and read back with a key that comes from ANOTHER hash's iteration. The
      # caller's `{}` and the callee's parameter are the same hash, so the keys
      # that the callee writes are the keys that the caller reads.
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
    result = zr(<<~'RUBY')
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
    result = zr(<<~'RUBY')
      # fetch(key, default) on a poly value that is actually a string-keyed hash
      # (here the nested hash reached via the outer hash's own fetch) must perform
      # the lookup, not collapse to the default.
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
    result = zr(<<~'RUBY')
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
    result = zr(<<~'RUBY')
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

      # String-keyed hashes (Integer values / String values) as values of another
      # hash: inspect shows them as hashes.
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
    result = zr(<<~'RUBY')
      # A Range in a mixed container: a hash literal mixes Integer values
      # with Range values, and each value keeps its class. Same shape for
      # mixed arrays.

      # Hash form (the Rails status-symbol table shape).
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
    result = zr(<<~'RUBY')
      # A receiver whose type is known only at run time, indexed by an Integer-or-nil
      # value (from an Integer => Integer hash lookup), answers the element.

      h = { 0 => 2, 1 => 3 }   # #[] returns Integer or nil
      k = h[0]                  # 2

      # A mixed literal makes `box` a mixed Array; its element can be of any type.
      box = [[10, 20, 30, 40, 50], "tail"]
      tbl = box[0]              # an Array of Integers at run time

      p tbl[k]                  # [] with an Integer-or-nil index -> want 30
    RUBY

    _(result).must_answer "30\n"
  end

  it "poly keyed hash pipeline" do
    result = zr(<<~'RUBY')
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
        # `item` gets a Method at one call site below and an Array of
        # Integers at another. The dedup reassignment
        # `item = @peeks[item] ||= item` works for both.
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
    result = zr(<<~'RUBY')
      # A `params = {}` filled with a computed String key and String values. A user
      # class also defines #length, so a call to `length` can go to either class.
      # `params.length` still answers the size of the hash.
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
    result = zr(<<~'RUBY')
      # `Hash#each_value { |v| ... }` on a hash with mixed keys and mixed
      # values runs the block for each value.
      #
      # The shape comes from optcarrot's PPU init
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
    result = zr(<<~'RUBY')
      # fetch and dup on a hash with mixed keys and mixed values. Two
      # writers to the same ivar use keys of different types (a param
      # and a Symbol literal), so the hash holds both kinds of key.

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
    result = zr(<<~'RUBY')
      # `merged[k] = v` where the types of merged AND k are known only at
      # run time. `[]=` goes to Hash#[]= because merged is a Hash, and the
      # key is the String that k holds.

      def get_poly(h, key)
        h[key]
      end

      def write_back(merged, k, v)
        merged[k] = v
      end

      def run(outer)
        merged = get_poly(outer, "m")
        # k and v come through a helper, so their types are known only
        # at run time.
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
    result = zr(<<~'RUBY')
      # Sibling to the example "poly recv fetch hash arms". A user class has a
      # `fetch` that only gets Symbol keys from its direct callers. A second call
      # site passes a String key to `fetch` on a Hash. At run time that receiver
      # is always a Hash, never the user class, so Hash#fetch answers.

      class FlashLike
        def fetch(key, default)
          @last = key
          default
        end
      end

      # Direct callers pass only Symbols to FlashLike#fetch's `key`.
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
    result = zr(<<~'RUBY')
      # `sub.fetch(k, d)` where sub came from a lookup in a hash with String
      # keys and mixed values. At run time sub is a Hash, so Hash#fetch does
      # the lookup and does not answer the default.
      #
      # A user-defined class with a `fetch` method makes the call site able
      # to reach either class.

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
    result = zr(<<~'RUBY')
      # `.dup` on a hash value read out of a hash with mixed values: the
      # call `outer[k].dup` answers a copy of the inner hash.
      #
      # The shape comes from a blog app's `merged = matched[:path_params].dup`.

      module Router
        def self.match(present)
          if present
            return { controller: :a, path_params: { "id" => "7" } }
          end
          nil
        end
      end

      # Sink consuming a hash of mixed type. The literal-init call below
      # passes such a hash.
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
    result = zr(<<~'RUBY')
      # Hash#each on a receiver whose type is known only at run time
      # runs the block for each pair. The block gets the pair as
      # `|k, v|`.

      module M
        def self.iter(hash)
          n = 0
          hash.each { |_k, _v| n += 1 }
          n
        end
      end

      # Two call sites pass different kinds of hash, so the param type is
      # known only at run time. Both shapes iterate.
      puts "a=#{M.iter({ a: 1, b: 2 })}"     # Symbol => Integer, expect 2
      puts "b=#{M.iter({ "x" => "y" })}"     # String => String, expect 1

      # Same surface with int-keyed hash + str values, an empty hash,
      # and a single-pair String => Integer hash. The third call drives the
      # per-iteration block param so we verify keys/values arrive.
      def m3(h)
        out = ""
        h.each { |k, v| out += k.to_s + "=" + v.to_s + ";" }
        out
      end

      puts m3({1 => "one", 2 => "two"})        # Integer => String
      puts m3({})                              # empty
      puts m3({"k" => 42})                     # String => Integer
    RUBY

    _(result).must_answer <<~'OUT'
      a=2
      b=1
      1=one;2=two;

      k=42;
    OUT
  end

  it "poly recv range sym hash dispatch" do
    result = zr(<<~'RUBY')
      # Two calls on built-in container types whose receiver type is known
      # only at run time.
      #
      # 1. `case x; when Range; r.include?(x); end` -- a value narrowed to a
      #    Range via case/when answers include? as a Range.
      #
      # 2. A lookup in a Symbol-keyed hash with a key narrowed by
      #    `is_a?(Symbol)`. The key can be a Symbol at run time.
      #
      # Also inspect on a Range read out of a hash with mixed values
      # answers "200..299", not "#<Object>".

      # --- 1: case/when narrowing to Range, then include?.
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

      # --- 2: sym-keyed hash with a key that comes from a
      # Symbol|Integer narrowing.
      H = { a: 200..299, b: 404, c: 500 }

      def lookup(expected)
        expected.is_a?(Symbol) ? H[expected] : expected
      end

      puts lookup(:a).inspect           # 200..299
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
    result = zr(<<~'RUBY')
      # `Hash#merge` on a Symbol-keyed hash with heterogeneous values
      # (Symbol => {Integer | String | Boolean | nil}). A non-mutating
      # `merge` answers a new hash with all the keys.
      #
      # The `[]` case covers a local that can hold values of more than one
      # type (e.g. because of an `is_a?` branch), while the value at run
      # time is such a hash.

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

      # 3. Symbol-key `[]` lookup on a local that can hold more than one
      #    type. The is_a?(String) branch puts a Hash in `opt`, and the
      #    reads of `merged[:k]` answer the merged values.
      def lookup(opt)
        # Mixed-value override hash for the `is_a?(String)` branch (and the
        # explicit-Hash call site too).
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
    result = zr(<<~'RUBY')
      # merge on a hash with Symbol keys and mixed values, with a
      # positional argument that has Symbol keys and Integer values.
      # The result holds the values of both.

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
