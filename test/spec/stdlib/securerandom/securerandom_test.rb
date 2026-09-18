# frozen_string_literal: true

require "spec_helper"

describe "SecureRandom programs" do
  it "builtin row reports its parameter names" do
    result = ze0(<<~'RUBY', files: {"securerandom.rb" => fixture("stdlib/securerandom/securerandom.rb")})
      # `Method#parameters` on a native row used to answer the anonymous descriptor
      # derived from its arity -- `[[:req]]` where ruby says `[[:req, :fmt]]`. zeo
      # reported a parameter NAME on no builtin row at all.
      #
      # The DSL now spells a row's signature (`params "fmt, buffer: nil"`), which is
      # ruby's own `def` spelling, and the ARITY falls out of it -- so the two
      # answers cannot disagree for a row that carries one. A keyword had no
      # spelling in the DSL before at all, because a native body receives one inside
      # the options Hash it already takes as a positional slot: what the body
      # RECEIVES and what ruby REPORTS are different questions.
      p Array.instance_method(:pack).parameters
      p Array.instance_method(:first).parameters
      p Array.instance_method(:sample).parameters
      p String.instance_method(:unpack1).parameters
      p IO.instance_method(:read_nonblock).parameters
      p Dir.method(:glob).parameters
      p Marshal.method(:load).parameters
      p Time.method(:at).parameters
      p TracePoint.instance_method(:enable).parameters

      # The arity a spelling implies is the one ruby derives from the same signature.
      p GC.method(:start).parameters
      p GC.method(:start).arity
      # ... and a `|`-joined sibling keeps its own, which is why the spelling is
      # per-NAME rather than per-def.
      p GC.method(:compact).parameters
      p GC.method(:compact).arity

      # An anonymous forwarding slot is named for its own sigil, ruby's own answer.
      p Ractor.instance_method(:send).parameters

      # A hand-registered exception row reaches no arity table, so zeo's two
      # catch-alls answered it differently: `-1` through `#arity` and `[]` through
      # `#parameters`. Every one of them is declared now, beside its ownership mark.
      p Exception.instance_method(:set_backtrace).parameters
      p Exception.instance_method(:set_backtrace).arity
      p Exception.instance_method(:full_message).parameters
      p Exception.instance_method(:message).parameters
      p NameError.instance_method(:receiver).arity
      p SystemExit.instance_method(:success?).arity

      # A `ruby def` spells the signature ONCE, in the parameter list, and the macro
      # derives both the binding and the report from it. `random` below is bound
      # directly as `Option<RubyValue>` -- the exact type the hand-written peel it
      # replaced returned -- so a converted row keeps its semantics.
      p Array.instance_method(:shuffle).parameters
      p Array.instance_method(:shuffle!).parameters

      # Ruby refuses a keyword the method does not declare. zeo used to ignore it
      # silently, because the whole options Hash arrived as one `**opts` slot that
      # nothing checked.
      begin
        [1, 2].shuffle(bogus: 1)
      rescue ArgumentError => e
        puts "ArgumentError: #{e.message}"
      end

      # A class method an `extend` supplies is an INSTANCE row seated in the
      # singleton chain, which the ancestry walk cannot see. `Method#owner` already
      # named the module; the signature lookup now takes the same route.
      require "securerandom"
      p SecureRandom.method(:alphanumeric).parameters
      p SecureRandom.method(:hex).parameters
      p SecureRandom.method(:hex).owner

      # `f(h)` and `f(**h)` are different calls, and ruby answers them three
      # different ways. Only the caller's KEYWORD MARK tells them apart, so a def
      # naming its keywords requires it -- a `**kwrest`-only def keeps the looser
      # rule it has always had, where any trailing Hash is keywords.
      h = { x: 1 }
      begin; [1, 2, 3].sample(h);   rescue Exception => e; puts "#{e.class}: #{e.message}"; end
      begin; [1, 2, 3].shuffle(h);  rescue Exception => e; puts "#{e.class}: #{e.message}"; end
      begin; [1, 2, 3].shuffle(**h); rescue Exception => e; puts "#{e.class}: #{e.message}"; end
    RUBY

    _(result).must_answer <<~'OUT'
      [[:req, :fmt], [:key, :buffer]]
      [[:opt, :n]]
      [[:opt, :n], [:key, :random]]
      [[:req, :fmt], [:key, :offset]]
      [[:req, :len], [:opt, :buf], [:key, :exception]]
      [[:req, :pattern], [:opt, :_flags], [:key, :flags], [:key, :base], [:key, :sort]]
      [[:req, :source], [:opt, :proc], [:key, :freeze]]
      [[:req, :time], [:opt, :subsec], [:opt, :unit], [:key, :in]]
      [[:key, :target], [:key, :target_line], [:key, :target_thread]]
      [[:key, :full_mark], [:key, :immediate_mark], [:key, :immediate_sweep]]
      -1
      []
      0
      [[:rest, :*], [:keyrest, :**], [:block, :&]]
      [[:req]]
      1
      [[:rest]]
      []
      0
      0
      [[:key, :random]]
      [[:key, :random]]
      ArgumentError: unknown keyword: :bogus
      [[:opt, :n], [:key, :chars]]
      [[:opt, :n]]
      Random::Formatter
      TypeError: no implicit conversion of Hash into Integer
      ArgumentError: wrong number of arguments (given 1, expected 0)
      ArgumentError: unknown keyword: :x
    OUT
  end

  it "is cryptographic not a seeded prng" do
    result = ze0(<<~'RUBY', files: {"securerandom.rb" => fixture("stdlib/securerandom/securerandom.rb")})
      # Two independent draws must differ, and -- unlike Kernel#rand -- srand must
      # NOT make SecureRandom reproducible (it reads the OS CSPRNG, not the seedable
      # generator). A regression to a clock-seeded xorshift would break this.

      require "securerandom"
      puts(SecureRandom.hex(16) != SecureRandom.hex(16))
      srand(42); a = SecureRandom.hex(16)
      srand(42); b = SecureRandom.hex(16)
      puts(a != b)
      # Random.urandom itself: correct bytesize, drawn fresh each call.
      puts Random.urandom(24).bytesize
      puts(Random.urandom(8) != Random.urandom(8))
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      24
      true
    OUT
  end

  it "securerandom" do
    result = ze0(<<~'RUBY')
      # SecureRandom: cryptographically secure random values, built on OS entropy
      # (Random.urandom) and the Random::Formatter mixin. Random output can't be
      # printed verbatim, so this prints its OBSERVABLE CONTRACT -- lengths, formats,
      # ranges, encoding -- which is identical under zeo and ruby.
      require "securerandom"

      # hex(n) -> 2n lowercase hex chars; default n is 16.
      puts SecureRandom.hex(8).length
      puts SecureRandom.hex.length
      puts(SecureRandom.hex(8) =~ /\A\h{16}\z/ ? "hex_ok" : "hex_BAD")

      # base64 / urlsafe_base64. n=5 isn't a multiple of 3, so a padded encoding
      # actually carries a trailing '=' -- default strips it, `true` keeps it.
      puts SecureRandom.base64(6).length
      puts(SecureRandom.urlsafe_base64(5) =~ /\A[A-Za-z0-9\-_]+\z/ ? "urlsafe_ok" : "urlsafe_BAD")
      puts SecureRandom.urlsafe_base64(5).include?("=")
      puts SecureRandom.urlsafe_base64(5, true).include?("=")

      # uuid -> a valid RFC 9562 version-4 UUID.
      puts(SecureRandom.uuid =~ /\A\h{8}-\h{4}-4\h{3}-[89ab]\h{3}-\h{12}\z/ ? "uuid_ok" : "uuid_BAD")

      # random_bytes -> a BINARY (ASCII-8BIT) string of the requested size.
      puts SecureRandom.random_bytes(5).bytesize
      puts SecureRandom.random_bytes(5).encoding.to_s

      # random_number: integer in [0, n), or a float in [0.0, 1.0) with no argument.
      puts((0...100).all? { SecureRandom.random_number(10) < 10 })
      puts SecureRandom.random_number.class
      puts((0...100).all? { r = SecureRandom.random_number; r >= 0.0 && r < 1.0 })

      # alphanumeric.
      puts(SecureRandom.alphanumeric(20) =~ /\A[A-Za-z0-9]{20}\z/ ? "alnum_ok" : "alnum_BAD")

      # Two independent draws differ (a seeded PRNG would not).
      puts(SecureRandom.hex(16) != SecureRandom.hex(16))
    RUBY

    _(result).must_answer <<~'OUT'
      16
      32
      hex_ok
      8
      urlsafe_ok
      false
      true
      uuid_ok
      5
      ASCII-8BIT
      true
      Float
      true
      alnum_ok
      true
    OUT
  end

  it "securerandom formatted lengths and types" do
    result = ze0(<<~'RUBY', files: {"securerandom.rb" => fixture("stdlib/securerandom/securerandom.rb")})
      require "securerandom"
      puts SecureRandom.hex(8).length          # 2*n
      puts SecureRandom.hex.length             # default n=16
      puts SecureRandom.hex(8).class
      puts SecureRandom.base64(6).length        # 4/3 * n, padded
      puts SecureRandom.random_bytes(5).bytesize
      puts SecureRandom.random_bytes(5).encoding.to_s
      puts SecureRandom.alphanumeric(12).length
      puts(SecureRandom.alphanumeric(20) =~ /\A[A-Za-z0-9]{20}\z/ ? "alnum_ok" : "alnum_BAD")
    RUBY

    _(result).must_answer <<~'OUT'
      16
      32
      String
      8
      5
      ASCII-8BIT
      12
      alnum_ok
    OUT
  end

  it "securerandom random number bounds" do
    result = ze0(<<~'RUBY', files: {"securerandom.rb" => fixture("stdlib/securerandom/securerandom.rb")})
      require "securerandom"
      puts SecureRandom.random_number(10).class
      puts (0...200).all? { SecureRandom.random_number(10) < 10 }
      puts (0...200).all? { n = SecureRandom.random_number(1); n == 0 }   # [0,1) integer => always 0
      puts SecureRandom.random_number.class                              # no arg => Float in [0,1)
      puts (0.0...1.0).include?(SecureRandom.random_number)
      puts SecureRandom.random_number(1.5).class                         # positive Float => Float
      # Range form
      r = SecureRandom.random_number(5..9)
      puts (5..9).include?(r)
    RUBY

    _(result).must_answer <<~'OUT'
      Integer
      true
      true
      Float
      true
      Float
      true
    OUT
  end

  it "securerandom urlsafe base64 padding rules" do
    result = ze0(<<~'RUBY', files: {"securerandom.rb" => fixture("stdlib/securerandom/securerandom.rb")})
      require "securerandom"
      # Default: no padding, URL/filename-safe alphabet only. n=5 isn't a
      # multiple of 3, so a padded encoding really does carry a trailing '='.
      s = SecureRandom.urlsafe_base64(5)
      puts(s =~ /\A[A-Za-z0-9\-_]+\z/ ? "urlsafe_ok" : "urlsafe_BAD: #{s}")
      puts s.include?("=")
      # Explicit padding: keeps the '='.
      puts SecureRandom.urlsafe_base64(5, true).include?("=")
    RUBY

    _(result).must_answer <<~'OUT'
      urlsafe_ok
      false
      true
    OUT
  end

  it "securerandom uuid is a valid v4" do
    result = ze0(<<~'RUBY', files: {"securerandom.rb" => fixture("stdlib/securerandom/securerandom.rb")})
      require "securerandom"
      u = SecureRandom.uuid
      puts(u =~ /\A\h{8}-\h{4}-4\h{3}-[89ab]\h{3}-\h{12}\z/ ? "uuid_ok" : "uuid_BAD: #{u}")
      puts(SecureRandom.uuid_v4 =~ /\A\h{8}-\h{4}-4\h{3}-[89ab]\h{3}-\h{12}\z/ ? "v4_ok" : "v4_BAD")
    RUBY

    _(result).must_answer <<~'OUT'
      uuid_ok
      v4_ok
    OUT
  end
end
