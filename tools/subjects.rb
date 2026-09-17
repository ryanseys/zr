# frozen_string_literal: true

# Which spec file a corpus case belongs in, and what to call it there.
#
# A case keeps the area it was filed under -- that is the directory --
# and the area is split by what each program is about, so `core/string`
# becomes `frozen_test.rb`, `encoding_test.rb`, `search_test.rb` and so
# on. The subjects are shared across areas, so the same kind of program
# has the same name wherever it sits.
#
# The table is a first pass: a rule that files a program oddly is meant
# to be edited, and a big `misc_test.rb` is the table asking to be grown.
module Subjects
  Subject = Struct.new(:key, :title, :pattern, :drop, keyword_init: true)

  def self.subject(key, title, pattern, drop: [])
    Subject.new(key: key, title: title, pattern: pattern, drop: drop)
  end

  # Ordered: a narrow rule sits above the wide one it would lose to.
  TABLE = [
    subject("frozen", "frozen literals", /frozen|chilled|dedup|fstring/, drop: %w[frozen chilled literal]),
    subject("encoding", "encodings", /encoding|encode|transcode|ascii|utf|unicode|codepoint|grapheme|scrub|binmode/,
            drop: %w[encoding]),
    subject("interpolation", "interpolation", /interpolat|interp|heredoc/, drop: %w[interpolation interpolated]),
    subject("case_mapping", "case mapping", /upcase|downcase|capitalize|swapcase|casecmp|titlecase|casefold/),
    subject("formatting", "formatting and inspection", /sprintf|format|inspect|to_s\b|ljust|rjust|center|pretty/),
    subject("packing", "packing and unpacking", /\bpack\b|unpack|\bbinary\b|byteslice|bytes\b/),
    subject("search", "searching and matching", /\bscan\b|\bmatch\b|\bindex\b|rindex|start_with|end_with|include\?|\bgrep\b/),
    subject("substitution", "substitution", /\bgsub\b|\bsub\b|\btr\b|squeeze|\bdelete\b|\breplace\b/),
    subject("splitting", "splitting and joining", /\bsplit\b|\bjoin\b|partition|\bchunk\b|each_line|each_char/),
    subject("slicing", "slicing", /slice|\baref\b|\baset\b|\brange\b|\bfirst\b|\blast\b|\btake\b|\bdrop\b/),
    subject("mutation", "changing in place", /concat|shovel|append|prepend|insert|\bclear\b|chomp|chop|strip|\bbang\b|in_place/),
    subject("comparison", "comparison and equality", /\beq\b|equal|\bcmp\b|spaceship|compar|\bhash_key\b|eql\?|identity/),
    subject("conversion", "conversion", /to_i\b|to_f\b|to_a\b|to_h\b|to_str|to_ary|to_proc|to_sym|coerce|duck/),
    subject("arithmetic", "arithmetic", /arith|\bplus\b|\bminus\b|overflow|\bdivide\b|modulo|bigint|\bpow\b|\bround\b/),
    subject("blocks", "blocks and yields", /\bblock\b|\byield\b|\bproc\b|lambda|\bcurry\b|block_given/),
    subject("enumeration", "enumeration", /each_|enumerat|\blazy\b|\bmap\b|\binject\b|\breduce\b|filter_map|\bsort\b|\bzip\b/),
    subject("attributes", "generated attribute methods", /attr_accessor|attr_reader|attr_writer|\battr\b/, drop: %w[attr]),
    subject("definition", "defining and naming methods", /define_method|\balias\b|\bundef\b|method_missing|respond_to|\bsend\b|\barity\b/),
    subject("visibility", "visibility", /private|protected|\bpublic\b|module_function/),
    subject("inheritance", "inheritance and ancestors", /\bsuper\b|ancestor|\binherit|subclass|\bprepend\b|\bextend\b|\binclude\b|refine/),
    subject("constants", "constants", /\bconstant|\bconst_|\bcref\b|autoload/),
    subject("ivars", "instance and class variables", /\bivar|instance_variable|class_variable|\bcvar/),
    subject("eval", "evaluating a string", /\beval\b|instance_eval|class_eval|module_eval|\bbinding\b/, drop: %w[eval]),
    subject("exceptions", "raising and rescuing", /\braise\b|rescue|exception|\bensure\b|\bretry\b|backtrace|\bthrow\b|\bcatch\b|\berror\b/),
    subject("control_flow", "control flow", /\bwhile\b|\buntil\b|\bloop\b|\bbreak\b|\bnext\b|\bredo\b|\breturn\b|\bcase_when\b|\bif\b|\bunless\b/),
    subject("pattern_matching", "pattern matching", /pattern|\bdeconstruct|\bcase_in\b|\bin_\b/),
    subject("threads", "threads, fibers and ractors", /\bthread|\bfiber|\bractor|\bmutex\b|\bqueue\b|concurren/),
    subject("gc", "the collector", /\bgc\b|gc_root|objectspace|object_space|finaliz|\bweak|\bheap\b/, drop: %w[gc]),
    subject("io", "reading and writing", /\bio_\b|\bio\b|stdout|stderr|stdin|\bpipe\b|\bfile\b|\bdir\b|\bpath\b|\bsocket\b/),
    subject("requires", "loading files", /require|\bload\b|\bfeature\b|load_path/),
    subject("dispatch", "dispatch", /\bpoly\b|\bdispatch\b|\bcache\b|\bguard\b|monomorph|\bcall_site\b|\bboxed\b|\bunbox/),
    subject("regressions", "regressions", /\bissue_\d|\bbundle_|\bbatch\d|wave\d|\bprobe_/, drop: %w[])
  ].freeze

  # An area's own word, as a reader would write it.
  TITLES = {
    "io" => "IO", "gc" => "GC", "json" => "JSON", "ffi" => "FFI", "uri" => "URI", "erb" => "ERB",
    "csv" => "CSV", "yaml" => "YAML", "rubyvm" => "RubyVM", "objectspace" => "ObjectSpace",
    "tracepoint" => "TracePoint", "openssl" => "OpenSSL", "stringio" => "StringIO", "strscan" => "StringScanner",
    "io_console" => "IO::console", "nkf" => "NKF", "zlib" => "Zlib", "digest" => "Digest", "etc" => "Etc",
    "pp" => "PP", "set" => "Set", "time" => "Time", "date" => "Date", "prism" => "Prism"
  }.freeze

  def self.title_of(area)
    word = area.split("/").last
    TITLES[word] || word.split("_").map(&:capitalize).join(" ")
  end

  # A subject file small enough that it says less than the area would.
  FEW = 8

  # How a whole area is filed. Placing one program at a time gives an
  # area thirty files of two examples each; an area is planned as a
  # whole, so a subject that drew a handful goes in with the rest.
  #
  # Answers `{ case path => [file, describe, drop] }`.
  def self.plan(area, cases)
    picked = cases.to_h { |rb, source| [rb, best_for(rb, source, area)] }
    counts = picked.each_value.tally
    general = "#{area.split("/").last}"
    picked.to_h do |rb, subject|
      key, title = if subject.nil? || counts[subject] < FEW
                     [general, "#{title_of(area)} programs"]
                   else
                     [subject.key, "#{title_of(area)}: #{subject.title}"]
                   end
      # The describe opens with the area's own word, so an example does
      # not repeat it either.
      word = area.split("/").last
      [rb, ["#{area}/#{key}_test.rb", title, (subject&.drop || []) + [word, word.chomp("s"), word[0, 3]]]]
    end
  end

  # The subject that fits `rb` best, or nil when none does.
  def self.best_for(rb, source, area)
    name = File.basename(rb, ".rb")
    # A subject that only repeats the area says nothing -- every program
    # in `lang/blocks` is about blocks -- so the area's own word is not
    # allowed to be the answer.
    word = area.split("/").last
    open = TABLE.reject { |s| s.key == word || s.key.chomp("s") == word.chomp("s") }
    best, = open.each_with_index.max_by { |s, i| [score(name, source, s), -i] }
    best if best && !score(name, source, best).zero?
  end

  # A word in the name counts for much more than the same word in the
  # source, and the word the name opens with counts for most: a program
  # called `array_frozen_slice_bang` is about Array, however many frozen
  # literals it holds. Both spellings of the name are tried, since a rule
  # may name `each_` or may name `scan`, and `_` is a word character to
  # `\b`.
  def self.score(name, source, subject)
    spelt = [name, name.tr("_", " ")]
    named = spelt.any? { |n| n.match?(subject.pattern) }
    in_source = source.match?(subject.pattern)
    return 0 unless named || in_source

    (named ? 10 : 0) + (head_of(name).any? { |h| h.match?(subject.pattern) } ? 20 : 0) + (in_source ? 1 : 0)
  end

  def self.head_of(name)
    words = name.split("_")
    words.shift if %w[a an the].include?(words.first)
    two = words.first(2)
    [words.first.to_s, two.join(" "), two.join("_")]
  end

  # The words a sentence turns on. A name that still starts with one of
  # these once the describe's own words come off reads as the describe's
  # continuation; one that does not has become a fragment, and keeps the
  # whole sentence instead.
  VERBS = %w[
    is are was were has have had does do did can cannot will wont
    answers becomes carries counts drops fails finds folds follows gives grows holds
    joins keeps knows leaves lives loses makes names needs opens prints raises reads
    returns rewrites runs says sees sends shows splits stands stays survives takes
    tells wants warns wins works writes yields adds asks builds calls catches
    changes closes comes ends frees gets goes lands maps moves passes picks puts
    refuses rejects releases reports resolves rescues resets rounds sets sorts
    starts stops strips throws tries turns uses walks accepts allows
    not no never only still always
  ].freeze

  # `a_frozen_string_is_not_duped` under "frozen literals" reads as
  # "is not duped": the words the describe already said come off, and
  # what is left is the sentence the example is.
  def self.name_for(rb, drop)
    whole = File.basename(rb, ".rb").split("_")
    whole.shift if %w[a an the].include?(whole.first)
    words = whole.dup
    words.shift while words.size > 1 && drop.include?(words.first)
    return whole.join(" ") if words.empty? || !VERBS.include?(words.first)

    words.join(" ")
  end
end
