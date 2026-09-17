# frozen_string_literal: true

require "spec_helper"

describe "Object: searching and matching" do
  it "boxs class method is absent from mains reflection" do
    result = ze0(<<~'RUBY', env: {"RUBY_BOX" => "1"}, ruby: ["-W:no-experimental"])
      # Reflection agrees with dispatch. A name the box defined must not appear
      # in main's `singleton_methods`, which reads a name set with no box axis of
      # its own.



      b = Ruby::Box.new
      b.eval("class Array; def self.zzz = 1; end")
      p Array.singleton_methods(false).include?(:zzz)
      p b.eval("Array.singleton_methods(false).include?(:zzz)")
    RUBY

    _(result).must_answer <<~'OUT'
      false
      true
    OUT
  end

  it "core method owners match" do
    skip "runs only on macos" unless ["macos"].include?(Ze0::Spec.platform)

    result = ze0(<<~'RUBY')

      # The methods each core class and module defines itself, by visibility,
      # and the constants it holds, as ruby 4.0 lists them. Names that rubygems
      # and irb's Binding#irb define are left out, and so is RubyVM's parse.y
      # surface: the ISEQ class and the AST's nodes.
      LATER = %i[Gem RUBYGEMS_ACTIVATION_MONITOR irb InstructionSequence Location Node parse parse_file].freeze
      GEMS = %i[gem gem_original_require require require_relative].freeze
      mods = [BasicObject, Object, Kernel, Module, Class, Comparable, Enumerable, NilClass, TrueClass, FalseClass,
              Integer, Float, Numeric, Rational, Complex, String, Symbol, Array, Hash, Range, Struct, Data, Set,
              Proc, Method, UnboundMethod, Binding, Exception, StandardError, NameError, NoMethodError, KeyError,
              StopIteration, FrozenError, SystemExit, SignalException, SystemCallError, UncaughtThrowError,
              IO, File, File::Stat, Dir, Time, Random, Regexp, MatchData, Encoding, Encoding::Converter,
              Enumerator, Enumerator::Lazy, Enumerator::Yielder, Enumerator::Generator, Enumerator::Chain,
              Enumerator::ArithmeticSequence, Enumerator::Product,
              Thread, Thread::Mutex, Thread::Queue, Thread::SizedQueue, Thread::ConditionVariable, ThreadGroup,
              Fiber, Process::Status, ObjectSpace::WeakMap, ObjectSpace::WeakKeyMap, Marshal, Math, GC, Process,
              Signal, Warning, TracePoint, Ractor, Refinement, ObjectSpace, FileTest, Errno::ENOENT,
              RubyVM, RubyVM::AbstractSyntaxTree, RubyVM::YJIT]
      mods.each do |m|
        rows = {
          public: m.public_instance_methods(false),
          protected: m.protected_instance_methods(false),
          private: m.private_instance_methods(false) - GEMS,
          singleton: m.singleton_methods(false),
          constants: m.constants(false)
        }
        rows.each do |kind, names|
          names -= LATER
          puts "#{m} #{kind}: #{names.sort.join(' ')}"
        end
      end




    RUBY

    _(result).must_answer "BasicObject public: ! != == __id__ __send__ equal? instance_eval instance_exec\nBasicObject protected: \nBasicObject private: initialize method_missing singleton_method_added singleton_method_removed singleton_method_undefined\nBasicObject singleton: \nBasicObject constants: BasicObject\nObject public: \nObject protected: \nObject private: \nObject singleton: \nObject constants: ARGF ARGV ArgumentError Array BasicObject Binding CROSS_COMPILING Class ClosedQueueError Comparable Complex ConditionVariable Data DidYouMean Dir ENV EOFError Encoding EncodingError Enumerable Enumerator Errno ErrorHighlight Exception FalseClass Fiber FiberError File FileTest Float FloatDomainError FrozenError GC GEMS Hash IO IOError IndexError Integer Interrupt Kernel KeyError LATER LoadError LocalJumpError Marshal MatchData Math Method Module Monitor MonitorMixin Mutex NameError NilClass NoMatchingPatternError NoMatchingPatternKeyError NoMemoryError NoMethodError NotImplementedError Numeric Object ObjectSpace Pathname Proc Process Queue RUBY_COPYRIGHT RUBY_DESCRIPTION RUBY_ENGINE RUBY_ENGINE_VERSION RUBY_PATCHLEVEL RUBY_PLATFORM RUBY_RELEASE_DATE RUBY_REVISION RUBY_VERSION Ractor Random Range RangeError Rational RbConfig Refinement Regexp RegexpError Ruby RubyVM RuntimeError STDERR STDIN STDOUT ScriptError SecurityError Set Signal SignalException SizedQueue StandardError StopIteration String Struct Symbol SyntaxError SyntaxSuggest SystemCallError SystemExit SystemStackError TOPLEVEL_BINDING Thread ThreadError ThreadGroup Time TracePoint TrueClass TypeError UnboundMethod UncaughtThrowError UnicodeNormalize Warning ZeroDivisionError\nKernel public: !~ <=> === class clone define_singleton_method display dup enum_for eql? extend freeze frozen? hash inspect instance_of? instance_variable_defined? instance_variable_get instance_variable_set instance_variables is_a? itself kind_of? method methods nil? object_id private_methods protected_methods public_method public_methods public_send remove_instance_variable respond_to? send singleton_class singleton_method singleton_methods tap then to_enum to_s yield_self\nKernel protected: \nKernel private: Array Complex Float Hash Integer Pathname Rational String __callee__ __dir__ __method__ ` abort at_exit autoload autoload? binding block_given? caller caller_locations catch eval exec exit exit! fail fork format gets global_variables initialize_clone initialize_copy initialize_dup instance_variables_to_inspect iterator? lambda load local_variables loop open p pp print printf proc putc puts raise rand readline readlines respond_to_missing? select set_trace_func sleep spawn sprintf srand syscall system test throw trace_var trap untrace_var warn\nKernel singleton: Array Complex Float Hash Integer Pathname Rational String __callee__ __dir__ __method__ ` abort at_exit autoload autoload? binding block_given? caller caller_locations catch eval exec exit exit! fail fork format gets global_variables iterator? lambda load local_variables loop open p print printf proc putc puts raise rand readline readlines require require_relative select set_trace_func sleep spawn sprintf srand syscall system test throw trace_var trap untrace_var warn\nKernel constants: \nModule public: < <= <=> == === > >= alias_method ancestors attr attr_accessor attr_reader attr_writer autoload autoload? class_eval class_exec class_variable_defined? class_variable_get class_variable_set class_variables const_defined? const_get const_missing const_set const_source_location constants define_method deprecate_constant freeze include include? included_modules inspect instance_method instance_methods method_defined? module_eval module_exec name prepend private_class_method private_constant private_instance_methods private_method_defined? protected_instance_methods protected_method_defined? public_class_method public_constant public_instance_method public_instance_methods public_method_defined? refinements remove_class_variable remove_method set_temporary_name singleton_class? to_s undef_method undefined_instance_methods\nModule protected: \nModule private: append_features const_added extend_object extended included initialize initialize_clone method_added method_removed method_undefined module_function prepend_features prepended private protected public refine remove_const ruby2_keywords using\nModule singleton: constants nesting used_modules used_refinements\nModule constants: \nClass public: allocate attached_object new subclasses superclass\nClass protected: \nClass private: inherited initialize\nClass singleton: allocate\nClass constants: \nComparable public: < <= == > >= between? clamp\nComparable protected: \nComparable private: \nComparable singleton: \nComparable constants: \nEnumerable public: all? any? chain chunk chunk_while collect collect_concat compact count cycle detect drop drop_while each_cons each_entry each_slice each_with_index each_with_object entries filter filter_map find find_all find_index first flat_map grep grep_v group_by include? inject lazy map max max_by member? min min_by minmax minmax_by none? one? partition reduce reject reverse_each select slice_after slice_before slice_when sort sort_by sum take take_while tally to_a to_h to_set uniq zip\nEnumerable protected: \nEnumerable private: \nEnumerable singleton: \nEnumerable constants: \nNilClass public: & === =~ ^ inspect nil? rationalize to_a to_c to_f to_h to_i to_r to_s |\nNilClass protected: \nNilClass private: \nNilClass singleton: \nNilClass constants: \nTrueClass public: & === ^ inspect to_s |\nTrueClass protected: \nTrueClass private: \nTrueClass singleton: \nTrueClass constants: \nFalseClass public: & === ^ inspect to_s |\nFalseClass protected: \nFalseClass private: \nFalseClass singleton: \nFalseClass constants: \nInteger public: % & * ** + - -@ / < << <= <=> == === > >= >> [] ^ abs allbits? anybits? bit_length ceil ceildiv chr coerce denominator digits div divmod downto even? fdiv floor gcd gcdlcm inspect integer? lcm magnitude modulo next nobits? numerator odd? ord pow pred rationalize remainder round size succ times to_f to_i to_int to_r to_s truncate upto zero? | ~\nInteger protected: \nInteger private: \nInteger singleton: sqrt try_convert\nInteger constants: \nFloat public: % * ** + - -@ / < <= <=> == === > >= abs angle arg ceil coerce denominator divmod eql? fdiv finite? floor hash infinite? inspect magnitude modulo nan? negative? next_float numerator phase positive? prev_float quo rationalize round to_f to_i to_int to_r to_s truncate zero?\nFloat protected: \nFloat private: \nFloat singleton: \nFloat constants: DIG EPSILON INFINITY MANT_DIG MAX MAX_10_EXP MAX_EXP MIN MIN_10_EXP MIN_EXP NAN RADIX\nNumeric public: % +@ -@ <=> abs abs2 angle arg ceil clone coerce conj conjugate denominator div divmod dup eql? fdiv finite? floor i imag imaginary infinite? integer? magnitude modulo negative? nonzero? numerator phase polar positive? quo real real? rect rectangular remainder round singleton_method_added step to_c to_int truncate zero?\nNumeric protected: \nNumeric private: \nNumeric singleton: \nNumeric constants: \nRational public: * ** + - -@ / <=> == abs ceil coerce denominator fdiv floor hash inspect magnitude negative? numerator positive? quo rationalize round to_f to_i to_r to_s truncate\nRational protected: \nRational private: marshal_dump\nRational singleton: \nRational constants: \nComplex public: * ** + - -@ / <=> == abs abs2 angle arg coerce conj conjugate denominator eql? fdiv finite? hash imag imaginary infinite? inspect magnitude numerator phase polar quo rationalize real real? rect rectangular to_c to_f to_i to_r to_s\nComplex protected: \nComplex private: marshal_dump\nComplex singleton: polar rect rectangular\nComplex constants: I\nString public: % * + +@ -@ << <=> == === =~ [] []= append_as_bytes ascii_only? b byteindex byterindex bytes bytesize byteslice bytesplice capitalize capitalize! casecmp casecmp? center chars chomp chomp! chop chop! chr clear codepoints concat count crypt dedup delete delete! delete_prefix delete_prefix! delete_suffix delete_suffix! downcase downcase! dump dup each_byte each_char each_codepoint each_grapheme_cluster each_line empty? encode encode! encoding end_with? eql? force_encoding freeze getbyte grapheme_clusters gsub gsub! hash hex include? index insert inspect intern length lines ljust lstrip lstrip! match match? next next! oct ord partition prepend replace reverse reverse! rindex rjust rpartition rstrip rstrip! scan scrub scrub! setbyte size slice slice! split squeeze squeeze! start_with? strip strip! sub sub! succ succ! sum swapcase swapcase! to_c to_f to_i to_r to_s to_str to_sym tr tr! tr_s tr_s! undump unicode_normalize unicode_normalize! unicode_normalized? unpack unpack1 upcase upcase! upto valid_encoding?\nString protected: \nString private: initialize initialize_copy\nString singleton: new try_convert\nString constants: \nSymbol public: <=> == === =~ [] capitalize casecmp casecmp? downcase empty? encoding end_with? id2name inspect intern length match match? name next size slice start_with? succ swapcase to_proc to_s to_sym upcase\nSymbol protected: \nSymbol private: \nSymbol singleton: all_symbols\nSymbol constants: \nArray public: & * + - << <=> == [] []= all? any? append assoc at bsearch bsearch_index clear collect collect! combination compact compact! concat count cycle deconstruct delete delete_at delete_if detect difference dig drop drop_while each each_index empty? eql? fetch fetch_values fill filter filter! find find_index first flatten flatten! freeze hash include? index insert inspect intersect? intersection join keep_if last length map map! max min minmax none? one? pack permutation pop prepend product push rassoc reject reject! repeated_combination repeated_permutation replace reverse reverse! reverse_each rfind rindex rotate rotate! sample select select! shift shuffle shuffle! size slice slice! sort sort! sort_by! sum take take_while to_a to_ary to_h to_s transpose union uniq uniq! unshift values_at zip |\nArray protected: \nArray private: initialize initialize_copy\nArray singleton: [] new try_convert\nArray constants: \nHash public: < <= == > >= [] []= any? assoc clear compact compact! compare_by_identity compare_by_identity? deconstruct_keys default default= default_proc default_proc= delete delete_if dig each each_key each_pair each_value empty? eql? except fetch fetch_values filter filter! flatten freeze has_key? has_value? hash include? inspect invert keep_if key key? keys length member? merge merge! rassoc rehash reject reject! replace select select! shift size slice store to_a to_h to_hash to_proc to_s transform_keys transform_keys! transform_values transform_values! update value? values values_at\nHash protected: \nHash private: initialize initialize_copy\nHash singleton: [] ruby2_keywords_hash ruby2_keywords_hash? try_convert\nHash constants: \nRange public: % == === begin bsearch count cover? each end entries eql? exclude_end? first hash include? inspect last max member? min minmax overlap? reverse_each size step to_a to_s to_set\nRange protected: \nRange private: initialize initialize_copy\nRange singleton: \nRange constants: \nStruct public: == [] []= deconstruct deconstruct_keys dig each each_pair eql? filter hash inspect length members select size to_a to_h to_s values values_at\nStruct protected: \nStruct private: initialize initialize_copy\nStruct singleton: new\nStruct constants: \nData public: == deconstruct deconstruct_keys eql? hash inspect members to_h to_s with\nData protected: \nData private: initialize initialize_copy\nData singleton: define\nData constants: \nSet public: & + - < << <= <=> == === > >= ^ add add? classify clear collect! compare_by_identity compare_by_identity? delete delete? delete_if difference disjoint? divide each empty? eql? filter! flatten flatten! hash include? inspect intersect? intersection join keep_if length map! member? merge proper_subset? proper_superset? reject! replace reset select! size subset? subtract superset? to_a to_s to_set union |\nSet protected: \nSet private: initialize initialize_copy\nSet singleton: []\nSet constants: CoreSet\nProc public: << == === >> [] arity binding call clone curry dup eql? hash inspect lambda? parameters ruby2_keywords source_location to_proc to_s yield\nProc protected: \nProc private: \nProc singleton: new\nProc constants: \nMethod public: << == === >> [] arity box call clone curry dup eql? hash inspect name original_name owner parameters receiver source_location super_method to_proc to_s unbind\nMethod protected: \nMethod private: \nMethod singleton: \nMethod constants: \nUnboundMethod public: == arity bind bind_call clone dup eql? hash inspect name original_name owner parameters source_location super_method to_s\nUnboundMethod protected: \nUnboundMethod private: \nUnboundMethod singleton: \nUnboundMethod constants: \nBinding public: clone dup eval implicit_parameter_defined? implicit_parameter_get implicit_parameters local_variable_defined? local_variable_get local_variable_set local_variables receiver source_location\nBinding protected: \nBinding private: \nBinding singleton: \nBinding constants: \nException public: == backtrace backtrace_locations cause detailed_message exception full_message inspect message respond_to? set_backtrace to_s\nException protected: \nException private: initialize method_missing respond_to_missing?\nException singleton: exception to_tty?\nException constants: \nStandardError public: \nStandardError protected: \nStandardError private: \nStandardError singleton: \nStandardError constants: \nNameError public: local_variables name receiver\nNameError protected: \nNameError private: initialize\nNameError singleton: \nNameError constants: \nNoMethodError public: args private_call?\nNoMethodError protected: \nNoMethodError private: initialize\nNoMethodError singleton: \nNoMethodError constants: \nKeyError public: key receiver\nKeyError protected: \nKeyError private: initialize\nKeyError singleton: \nKeyError constants: \nStopIteration public: result\nStopIteration protected: \nStopIteration private: \nStopIteration singleton: \nStopIteration constants: \nFrozenError public: receiver\nFrozenError protected: \nFrozenError private: initialize\nFrozenError singleton: \nFrozenError constants: \nSystemExit public: status success?\nSystemExit protected: \nSystemExit private: initialize\nSystemExit singleton: \nSystemExit constants: \nSignalException public: signm signo\nSignalException protected: \nSignalException private: initialize\nSignalException singleton: \nSignalException constants: \nSystemCallError public: errno\nSystemCallError protected: \nSystemCallError private: initialize\nSystemCallError singleton: ===\nSystemCallError constants: \nUncaughtThrowError public: tag to_s value\nUncaughtThrowError protected: \nUncaughtThrowError private: initialize\nUncaughtThrowError singleton: \nUncaughtThrowError constants: \nIO public: << advise autoclose= autoclose? binmode binmode? close close_on_exec= close_on_exec? close_read close_write closed? each each_byte each_char each_codepoint each_line eof eof? external_encoding fcntl fdatasync fileno flush fsync getbyte getc gets inspect internal_encoding ioctl isatty lineno lineno= path pid pos pos= pread print printf putc puts pwrite read read_nonblock readbyte readchar readline readlines readpartial reopen rewind seek set_encoding set_encoding_by_bom stat sync sync= sysread sysseek syswrite tell timeout timeout= to_i to_io to_path tty? ungetbyte ungetc wait wait_priority wait_readable wait_writable write write_nonblock\nIO protected: \nIO private: initialize initialize_copy\nIO singleton: binread binwrite copy_stream for_fd foreach new open pipe popen read readlines select sysopen try_convert write\nIO constants: Buffer EAGAINWaitReadable EAGAINWaitWritable EINPROGRESSWaitReadable EINPROGRESSWaitWritable EWOULDBLOCKWaitReadable EWOULDBLOCKWaitWritable PRIORITY READABLE SEEK_CUR SEEK_DATA SEEK_END SEEK_HOLE SEEK_SET TimeoutError WRITABLE WaitReadable WaitWritable\nFile public: atime birthtime chmod chown ctime flock lstat mtime size truncate\nFile protected: \nFile private: initialize\nFile singleton: absolute_path absolute_path? atime basename birthtime blockdev? chardev? chmod chown ctime delete directory? dirname empty? executable? executable_real? exist? expand_path extname file? fnmatch fnmatch? ftype grpowned? identical? join lchmod lchown link lstat lutime mkfifo mtime owned? path pipe? readable? readable_real? readlink realdirpath realpath rename setgid? setuid? size size? socket? split stat sticky? symlink symlink? truncate umask unlink utime world_readable? world_writable? writable? writable_real? zero?\nFile constants: ALT_SEPARATOR Constants PATH_SEPARATOR SEPARATOR Separator Stat\nFile::Stat public: <=> atime birthtime blksize blockdev? blocks chardev? ctime dev dev_major dev_minor directory? executable? executable_real? file? ftype gid grpowned? ino inspect mode mtime nlink owned? pipe? rdev rdev_major rdev_minor readable? readable_real? setgid? setuid? size size? socket? sticky? symlink? uid world_readable? world_writable? writable? writable_real? zero?\nFile::Stat protected: \nFile::Stat private: initialize initialize_copy\nFile::Stat singleton: \nFile::Stat constants: \nDir public: chdir children close each each_child fileno inspect path pos pos= read rewind seek tell to_path\nDir protected: \nDir private: initialize\nDir singleton: [] chdir children chroot delete each_child empty? entries exist? fchdir for_fd foreach getwd glob home mkdir open pwd rmdir unlink\nDir constants: \nTime public: + - <=> asctime ceil ctime day deconstruct_keys dst? eql? floor friday? getgm getlocal getutc gmt? gmt_offset gmtime gmtoff hash hour inspect isdst iso8601 localtime mday min mon monday? month nsec round saturday? sec strftime subsec sunday? thursday? to_a to_f to_i to_r to_s tuesday? tv_nsec tv_sec tv_usec usec utc utc? utc_offset wday wednesday? xmlschema yday year zone\nTime protected: \nTime private: _dump initialize initialize_copy\nTime singleton: at gm local mktime now utc\nTime constants: \nRandom public: ==\nRandom protected: \nRandom private: initialize_copy left marshal_dump marshal_load state\nRandom singleton: bytes new_seed rand seed srand urandom\nRandom constants: Base Formatter\nRegexp public: == === =~ casefold? encoding eql? fixed_encoding? hash inspect match match? named_captures names options source timeout to_s ~\nRegexp protected: \nRegexp private: initialize initialize_copy\nRegexp singleton: compile escape last_match linear_time? quote timeout timeout= try_convert union\nRegexp constants: EXTENDED FIXEDENCODING IGNORECASE MULTILINE NOENCODING TimeoutError\nMatchData public: == [] begin bytebegin byteend byteoffset captures deconstruct deconstruct_keys end eql? hash inspect length match match_length named_captures names offset post_match pre_match regexp size string to_a to_s values_at\nMatchData protected: \nMatchData private: initialize_copy\nMatchData singleton: \nMatchData constants: \nEncoding public: _dump ascii_compatible? dummy? inspect name names to_s\nEncoding protected: \nEncoding private: \nEncoding singleton: _load aliases compatible? default_external default_external= default_internal default_internal= find list locale_charmap name_list\nEncoding constants: ANSI_X3_4_1968 ASCII ASCII_8BIT BIG5 BIG5_HKSCS BIG5_HKSCS_2008 BIG5_UAO BINARY Big5 Big5_HKSCS Big5_HKSCS_2008 Big5_UAO CESU_8 CP1250 CP1251 CP1252 CP1253 CP1254 CP1255 CP1256 CP1257 CP1258 CP437 CP50220 CP50221 CP51932 CP65000 CP65001 CP720 CP737 CP775 CP850 CP852 CP855 CP857 CP860 CP861 CP862 CP863 CP864 CP865 CP866 CP869 CP874 CP878 CP932 CP936 CP949 CP950 CP951 CSWINDOWS31J CompatibilityError Converter ConverterNotFoundError CsWindows31J EBCDIC_CP_US EMACS_MULE EUCCN EUCJP EUCJP_MS EUCKR EUCTW EUC_CN EUC_JISX0213 EUC_JIS_2004 EUC_JP EUC_JP_MS EUC_KR EUC_TW Emacs_Mule EucCN EucJP EucJP_ms EucKR EucTW GB12345 GB18030 GB1988 GB2312 GBK IBM037 IBM437 IBM720 IBM737 IBM775 IBM850 IBM852 IBM855 IBM857 IBM860 IBM861 IBM862 IBM863 IBM864 IBM865 IBM866 IBM869 ISO2022_JP ISO2022_JP2 ISO8859_1 ISO8859_10 ISO8859_11 ISO8859_13 ISO8859_14 ISO8859_15 ISO8859_16 ISO8859_2 ISO8859_3 ISO8859_4 ISO8859_5 ISO8859_6 ISO8859_7 ISO8859_8 ISO8859_9 ISO_2022_JP ISO_2022_JP_2 ISO_2022_JP_KDDI ISO_8859_1 ISO_8859_10 ISO_8859_11 ISO_8859_13 ISO_8859_14 ISO_8859_15 ISO_8859_16 ISO_8859_2 ISO_8859_3 ISO_8859_4 ISO_8859_5 ISO_8859_6 ISO_8859_7 ISO_8859_8 ISO_8859_9 InvalidByteSequenceError KOI8_R KOI8_U MACCENTEURO MACCROATIAN MACCYRILLIC MACGREEK MACICELAND MACJAPAN MACJAPANESE MACROMAN MACROMANIA MACTHAI MACTURKISH MACUKRAINE MacCentEuro MacCroatian MacCyrillic MacGreek MacIceland MacJapan MacJapanese MacRoman MacRomania MacThai MacTurkish MacUkraine PCK SHIFT_JIS SJIS SJIS_DOCOMO SJIS_DoCoMo SJIS_KDDI SJIS_SOFTBANK SJIS_SoftBank STATELESS_ISO_2022_JP STATELESS_ISO_2022_JP_KDDI Shift_JIS Stateless_ISO_2022_JP Stateless_ISO_2022_JP_KDDI TIS_620 UCS_2BE UCS_4BE UCS_4LE UNICODE_VERSION US_ASCII UTF8_DOCOMO UTF8_DoCoMo UTF8_KDDI UTF8_MAC UTF8_SOFTBANK UTF8_SoftBank UTF_16 UTF_16BE UTF_16LE UTF_32 UTF_32BE UTF_32LE UTF_7 UTF_8 UTF_8_HFS UTF_8_MAC UndefinedConversionError WINDOWS_1250 WINDOWS_1251 WINDOWS_1252 WINDOWS_1253 WINDOWS_1254 WINDOWS_1255 WINDOWS_1256 WINDOWS_1257 WINDOWS_1258 WINDOWS_31J WINDOWS_874 Windows_1250 Windows_1251 Windows_1252 Windows_1253 Windows_1254 Windows_1255 Windows_1256 Windows_1257 Windows_1258 Windows_31J Windows_874\nEncoding::Converter public: == convert convpath destination_encoding finish insert_output inspect last_error primitive_convert primitive_errinfo putback replacement replacement= source_encoding\nEncoding::Converter protected: \nEncoding::Converter private: initialize\nEncoding::Converter singleton: asciicompat_encoding search_convpath\nEncoding::Converter constants: AFTER_OUTPUT CRLF_NEWLINE_DECORATOR CR_NEWLINE_DECORATOR INVALID_MASK INVALID_REPLACE LF_NEWLINE_DECORATOR PARTIAL_INPUT UNDEF_HEX_CHARREF UNDEF_MASK UNDEF_REPLACE UNIVERSAL_NEWLINE_DECORATOR XML_ATTR_CONTENT_DECORATOR XML_ATTR_QUOTE_DECORATOR XML_TEXT_DECORATOR\nEnumerator public: + each each_with_index each_with_object feed inspect next next_values peek peek_values rewind size with_index with_object\nEnumerator protected: \nEnumerator private: initialize initialize_copy\nEnumerator singleton: produce product\nEnumerator constants: ArithmeticSequence Chain Generator Lazy Producer Product Yielder\nEnumerator::Lazy public: chunk chunk_while collect collect_concat compact drop drop_while eager enum_for filter filter_map find_all flat_map force grep grep_v lazy map reject select slice_after slice_before slice_when take take_while to_enum uniq with_index zip\nEnumerator::Lazy protected: \nEnumerator::Lazy private: _enumerable_collect _enumerable_collect_concat _enumerable_drop _enumerable_drop_while _enumerable_filter _enumerable_filter_map _enumerable_find_all _enumerable_flat_map _enumerable_grep _enumerable_grep_v _enumerable_map _enumerable_reject _enumerable_select _enumerable_take _enumerable_take_while _enumerable_uniq _enumerable_with_index _enumerable_zip initialize\nEnumerator::Lazy singleton: \nEnumerator::Lazy constants: \nEnumerator::Yielder public: << to_proc yield\nEnumerator::Yielder protected: \nEnumerator::Yielder private: initialize\nEnumerator::Yielder singleton: \nEnumerator::Yielder constants: \nEnumerator::Generator public: each\nEnumerator::Generator protected: \nEnumerator::Generator private: initialize initialize_copy\nEnumerator::Generator singleton: \nEnumerator::Generator constants: \nEnumerator::Chain public: each inspect rewind size\nEnumerator::Chain protected: \nEnumerator::Chain private: initialize initialize_copy\nEnumerator::Chain singleton: \nEnumerator::Chain constants: \nEnumerator::ArithmeticSequence public: == === begin each end eql? exclude_end? first hash inspect last size step\nEnumerator::ArithmeticSequence protected: \nEnumerator::ArithmeticSequence private: \nEnumerator::ArithmeticSequence singleton: \nEnumerator::ArithmeticSequence constants: \nEnumerator::Product public: each inspect rewind size\nEnumerator::Product protected: \nEnumerator::Product private: initialize initialize_copy\nEnumerator::Product singleton: \nEnumerator::Product constants: \nThread public: [] []= abort_on_exception abort_on_exception= add_trace_func alive? backtrace backtrace_locations exit fetch group inspect join key? keys kill name name= native_thread_id pending_interrupt? priority priority= raise report_on_exception report_on_exception= run set_trace_func status stop? terminate thread_variable? thread_variable_get thread_variable_set thread_variables to_s value wakeup\nThread protected: \nThread private: initialize\nThread singleton: abort_on_exception abort_on_exception= current each_caller_location exit fork handle_interrupt ignore_deadlock ignore_deadlock= kill list main new pass pending_interrupt? report_on_exception report_on_exception= start stop\nThread constants: Backtrace ConditionVariable Mutex Queue SizedQueue\nThread::Mutex public: lock locked? owned? sleep synchronize try_lock unlock\nThread::Mutex protected: \nThread::Mutex private: initialize\nThread::Mutex singleton: \nThread::Mutex constants: \nThread::Queue public: << clear close closed? deq empty? enq freeze length marshal_dump num_waiting pop push shift size\nThread::Queue protected: \nThread::Queue private: initialize\nThread::Queue singleton: \nThread::Queue constants: \nThread::SizedQueue public: << clear close deq enq max max= num_waiting pop push shift\nThread::SizedQueue protected: \nThread::SizedQueue private: initialize\nThread::SizedQueue singleton: \nThread::SizedQueue constants: \nThread::ConditionVariable public: broadcast marshal_dump signal wait\nThread::ConditionVariable protected: \nThread::ConditionVariable private: initialize\nThread::ConditionVariable singleton: \nThread::ConditionVariable constants: \nThreadGroup public: add enclose enclosed? list\nThreadGroup protected: \nThreadGroup private: \nThreadGroup singleton: \nThreadGroup constants: Default\nFiber public: alive? backtrace backtrace_locations blocking? inspect kill raise resume storage storage= to_s transfer\nFiber protected: \nFiber private: initialize\nFiber singleton: [] []= blocking blocking? current current_scheduler schedule scheduler set_scheduler yield\nFiber constants: \nProcess::Status public: == coredump? exited? exitstatus inspect pid signaled? stopped? stopsig success? termsig to_i to_s\nProcess::Status protected: \nProcess::Status private: \nProcess::Status singleton: wait\nProcess::Status constants: \nObjectSpace::WeakMap public: [] []= delete each each_key each_pair each_value include? inspect key? keys length member? size values\nObjectSpace::WeakMap protected: \nObjectSpace::WeakMap private: \nObjectSpace::WeakMap singleton: \nObjectSpace::WeakMap constants: \nObjectSpace::WeakKeyMap public: [] []= clear delete getkey inspect key?\nObjectSpace::WeakKeyMap protected: \nObjectSpace::WeakKeyMap private: \nObjectSpace::WeakKeyMap singleton: \nObjectSpace::WeakKeyMap constants: \nMarshal public: \nMarshal protected: \nMarshal private: dump\nMarshal singleton: dump load restore\nMarshal constants: MAJOR_VERSION MINOR_VERSION\nMath public: \nMath protected: \nMath private: acos acosh asin asinh atan atan2 atanh cbrt cos cosh erf erfc exp expm1 frexp gamma hypot ldexp lgamma log log10 log1p log2 sin sinh sqrt tan tanh\nMath singleton: acos acosh asin asinh atan atan2 atanh cbrt cos cosh erf erfc exp expm1 frexp gamma hypot ldexp lgamma log log10 log1p log2 sin sinh sqrt tan tanh\nMath constants: DomainError E PI\nGC public: garbage_collect\nGC protected: \nGC private: \nGC singleton: auto_compact auto_compact= compact config count disable enable latest_compact_info latest_gc_info measure_total_time measure_total_time= start stat stat_heap stress stress= total_time verify_compaction_references verify_internal_consistency\nGC constants: INTERNAL_CONSTANTS OPTS Profiler\nProcess public: \nProcess protected: \nProcess private: argv0 clock_getres clock_gettime daemon detach egid egid= euid euid= getpgid getpgrp getpriority getrlimit getsid gid gid= groups groups= initgroups kill maxgroups maxgroups= pid ppid setpgid setpgrp setpriority setproctitle setrlimit setsid times uid uid= wait wait2 waitall waitpid waitpid2 warmup\nProcess singleton: _fork abort argv0 clock_getres clock_gettime daemon detach egid egid= euid euid= exec exit exit! fork getpgid getpgrp getpriority getrlimit getsid gid gid= groups groups= initgroups kill last_status maxgroups maxgroups= pid ppid setpgid setpgrp setpriority setproctitle setrlimit setsid spawn times uid uid= wait wait2 waitall waitpid waitpid2 warmup\nProcess constants: CLOCK_MONOTONIC CLOCK_MONOTONIC_RAW CLOCK_MONOTONIC_RAW_APPROX CLOCK_PROCESS_CPUTIME_ID CLOCK_REALTIME CLOCK_THREAD_CPUTIME_ID CLOCK_UPTIME_RAW CLOCK_UPTIME_RAW_APPROX GID PRIO_PGRP PRIO_PROCESS PRIO_USER RLIMIT_AS RLIMIT_CORE RLIMIT_CPU RLIMIT_DATA RLIMIT_FSIZE RLIMIT_MEMLOCK RLIMIT_NOFILE RLIMIT_NPROC RLIMIT_RSS RLIMIT_STACK RLIM_INFINITY RLIM_SAVED_CUR RLIM_SAVED_MAX Status Sys Tms UID WNOHANG WUNTRACED Waiter\nSignal public: \nSignal protected: \nSignal private: list signame trap\nSignal singleton: list signame trap\nSignal constants: \nWarning public: warn\nWarning protected: \nWarning private: \nWarning singleton: [] []= categories\nWarning constants: \nTracePoint public: binding callee_id defined_class disable enable enabled? eval_script event inspect instruction_sequence lineno method_id parameters path raised_exception return_value self\nTracePoint protected: \nTracePoint private: \nTracePoint singleton: allow_reentry new stat trace\nTracePoint constants: \nRactor public: << [] []= close default_port inspect join monitor name send to_s unmonitor value\nRactor protected: \nRactor private: receive recv\nRactor singleton: [] []= _require count current main main? make_shareable new receive recv select shareable? shareable_lambda shareable_proc store_if_absent\nRactor constants: ClosedError Error IsolationError MovedError MovedObject Port RemoteError UnsafeError\nRefinement public: target\nRefinement protected: \nRefinement private: import_methods\nRefinement singleton: \nRefinement constants: \nObjectSpace public: \nObjectSpace protected: \nObjectSpace private: _id2ref count_objects define_finalizer each_object garbage_collect undefine_finalizer\nObjectSpace singleton: _id2ref count_objects define_finalizer each_object garbage_collect undefine_finalizer\nObjectSpace constants: WeakKeyMap WeakMap\nFileTest public: \nFileTest protected: \nFileTest private: blockdev? chardev? directory? empty? executable? executable_real? exist? file? grpowned? identical? owned? pipe? readable? readable_real? setgid? setuid? size size? socket? sticky? symlink? world_readable? world_writable? writable? writable_real? zero?\nFileTest singleton: blockdev? chardev? directory? empty? executable? executable_real? exist? file? grpowned? identical? owned? pipe? readable? readable_real? setgid? setuid? size size? socket? sticky? symlink? world_readable? world_writable? writable? writable_real? zero?\nFileTest constants: \nErrno::ENOENT public: \nErrno::ENOENT protected: \nErrno::ENOENT private: \nErrno::ENOENT singleton: \nErrno::ENOENT constants: Errno\nRubyVM public: \nRubyVM protected: \nRubyVM private: \nRubyVM singleton: keep_script_lines keep_script_lines= stat\nRubyVM constants: AbstractSyntaxTree DEFAULT_PARAMS INSTRUCTION_NAMES OPTS YJIT\nRubyVM::AbstractSyntaxTree public: \nRubyVM::AbstractSyntaxTree protected: \nRubyVM::AbstractSyntaxTree private: \nRubyVM::AbstractSyntaxTree singleton: node_id_for_backtrace_location of\nRubyVM::AbstractSyntaxTree constants: \nRubyVM::YJIT public: \nRubyVM::YJIT protected: \nRubyVM::YJIT private: \nRubyVM::YJIT singleton: code_gc disasm dump_exit_locations enable enabled? exit_locations insns_compiled log log_enabled? reset_stats! runtime_stats simulate_oom! stats_enabled? stats_string trace_exit_locations_enabled?\nRubyVM::YJIT constants: \n"
  end

  it "define singleton method in a def installs at runtime" do
    result = ze0(<<~'RUBY')
      # `SomeClass.define_singleton_method(:name) { }` written INSIDE a method
      # body (cannon and `by` retarget class methods mid-run; rails_admin
      # intercepts Object.const_missing this way) is a runtime overlay install,
      # not a class reopen -- there is no class-body site to register in a def.
      # (Whether a runtime-installed `const_missing` HOOK is consulted by a
      # folded constant read is the separate, documented divergence in
      # const_missing_on_a_named_class.rb.)
      class Router
        def self.routes
          "static routes"
        end
      end

      class App
        def boot(answer)
          Router.define_singleton_method(:routes) { "runtime #{answer}" }
        end
      end

      p Router.routes
      App.new.boot(42)
      p Router.routes
      p Router.singleton_methods.include?(:routes)

      # A fresh singleton method (no static row at all), with a capture.
      class Gauge; end
      def calibrate(offset)
        Gauge.define_singleton_method(:read) { 100 + offset }
      end
      calibrate(7)
      p Gauge.read

      # Receiverless inside a def installs on the method's own self.
      class Widget
        def specialize
          define_singleton_method(:kind) { :special }
          self
        end
      end
      w = Widget.new.specialize
      p w.kind
      p Widget.new.respond_to?(:kind)
      puts "still running"
    RUBY

    _(result).must_answer <<~'OUT'
      "static routes"
      "runtime 42"
      true
      107
      :special
      false
      still running
    OUT
  end

  it "enum chain with index object" do
    _(ze0(<<~'RUBY')).must_answer "0a1b2c\n10:x 11:y \n[2, 4, 6]\n2\n"
      # str.each_char.with_index (block form) and enum.each.with_object desugar
      # into the shapes the chain emitters already serve.
      "abc".each_char.with_index { |c, i| print "#{i}#{c}" }
      puts
      "xy".each_char.with_index(10) { |c, i| print "#{i}:#{c} " }
      puts
      x = [1, 2, 3].each.with_object([]) { |v, a| a << v * 2 }
      p x
      h = [1, 2].each.with_object({}) { |v, acc| acc[v.to_s] = v }
      p h.size
    RUBY
  end

  it "is a and instance of answer through class values" do
    result = ze0(<<~'RUBY')
      class Widget
      end
      module Helper
      end

      w = Widget.new
      puts w.instance_of?(Widget)
      puts w.instance_of?(Object)
      puts 5.instance_of?(Integer)
      puts Widget.is_a?(Class)
      puts Widget.is_a?(Module)
      puts Helper.is_a?(Module)
      puts Helper.is_a?(Class)
      puts Widget.ancestors.first == Widget
      puts Widget.ancestors.include?(Object)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      true
      true
      true
      true
      false
      true
      true
    OUT
  end

  it "is a included module" do
    result = ze0(<<~'RUBY')
      module M
        def foo; 42; end
      end

      module N
      end

      class C
        include M
      end

      class D
        include M
        include N
      end

      c = C.new
      p c.foo
      p c.is_a?(M)
      p c.is_a?(N)
      p C.ancestors.include?(M)
      p C.ancestors.include?(N)

      d = D.new
      p d.is_a?(M)
      p d.is_a?(N)
      p D.ancestors.include?(M)
      p D.ancestors.include?(N)
    RUBY

    _(result).must_answer <<~'OUT'
      42
      true
      false
      true
      false
      true
      true
      true
      true
    OUT
  end

  it "is a undefined const" do
    result = ze0(<<~'RUBY')
      # x.is_a?(NoSuchConst): the is_a?-family arms match the target constant
      # textually and never emit the constant read, so an undefined constant
      # silently answered false where CRuby raises NameError.
      [5, "s", String].each do |x|
        begin
          x.is_a?(NoSuchConst)
          puts "no raise"
        rescue NameError => e
          puts "NameError: #{e.message}"
        end
      end
      # defined targets keep their answers
      p 5.is_a?(Integer)
      p 5.is_a?(Comparable)
      p String.is_a?(Module)
      p String.is_a?(Comparable)
    RUBY

    _(result).must_answer <<~'OUT'
      NameError: uninitialized constant NoSuchConst
      NameError: uninitialized constant NoSuchConst
      NameError: uninitialized constant NoSuchConst
      true
      true
      true
      false
    OUT
  end

  it "nil sentinel from index compact" do
    result = ze0(<<~'RUBY')
      # A miss from String#index / #rindex is nil, and every consumer has to agree:
      # an int slot carrying the nil sentinel must box as nil, so compact drops it
      # and filter_map treats it as falsy.
      v = "a".rindex("/")
      w = "abc".index("b")
      p v.nil?
      p v.class
      p [v, 1].compact
      p [v, 1].filter_map { |x| x }
      p [v, w, 3].compact
      p [v, 1].compact.size
      p [1, v, 2].compact.sum

      # the same for an out-of-range slice on a String array and a Float miss
      s = "x"[5, 1]
      p [s, "y"].compact
      g = [].first
      p [g, 1.5].compact

      # a live nil in the same position still behaves
      p [nil, 1].compact
      p [v].compact.empty?
    RUBY

    _(result).must_answer <<~'OUT'
      true
      NilClass
      [1]
      [1]
      [1, 3]
      1
      3
      ["y"]
      [1.5]
      [1]
      true
    OUT
  end
end
