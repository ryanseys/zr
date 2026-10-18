# frozen_string_literal: true

module Zr
  # How each piece of the kernel's shared state stays consistent when Ruby
  # threads run on OS threads of their own: every static and global that
  # the kernel declares (`Machine.static`, `Machine.global`) and every slot
  # of the globals table (`G_*`).
  #
  # Each entry says two things. `now` is the rule under the GVL, where one
  # OS thread at a time runs the kernel:
  #
  # - `:thread`: each thread has its own value. A GVL handoff saves the
  #   word into the thread's fiber and loads the next thread's, as a fiber
  #   switch does (kernel/gvl.rb).
  # - `:gvl`: only the thread that holds the GVL reads or writes it.
  # - `:boot`: written before the program's first line, read only after.
  # - `:async`: written outside the GVL, by a signal handler, the timer
  #   thread or C that runs without the GVL. Each write is one aligned
  #   word, and the GVL holder reads it at a safe point.
  #
  # `free` is the plan for threads with no GVL (`--threads=parallel`):
  # `:per_thread` (it moves into each thread's state), `:immutable`,
  # `:atomic` (atomic loads, stores and adds), `:vm_lock` (the lock that
  # guards definitions and the shared tables), `:stopped` (only while
  # every other thread waits at a safe point, as the collector runs) or
  # `:main` (only the main thread touches it).
  #
  # `test/unit/lock_plan_test.rb` checks that every static, global and
  # slot of the kernel has an entry, and that every entry names one. New
  # kernel state adds its entry with it.
  module LockPlan
    Entry = Data.define(:now, :free, :note)

    NOW = %i[thread gvl boot async].freeze #: Array[Symbol]
    FREE = %i[per_thread immutable atomic vm_lock stopped main].freeze #: Array[Symbol]

    # [now, free, note, names]: one row for the names that share a rule.
    ROWS = [
      [:thread, :per_thread, "the running fiber, its task and its kernel root frames",
       %w[current_fiber current_task kroots]],

      [:async, :atomic, "a signal handler counts each signal and asks the next safe point; the preemption count is the wasm clock",
       %w[signal_counts signal_pending preempt_count]],
      [:async, :atomic, "SIGCHLD's handler counts children and writes to the waiters' pipe, which the GVL holder makes once",
       %w[chld_count chld_pipe]],
      [:async, :atomic, "the fatal-signal handler's state, which any thread that faults reads and writes",
       %w[crash_armed crash_bug crash_done crash_out crash_signal crash_template]],
      [:async, :atomic, "rb_postponed_job_trigger may run in a signal handler; registration is under the GVL",
       %w[postponed_data postponed_funcs postponed_marks postponed_pending]],
      [:async, :atomic, "the GVL's free flag and the threads back from a region, under the GVL's own mutex",
       %w[gvl]],
      [:async, :atomic, "C without the GVL posts its jobs through the pool's own mutex",
       %w[offload_pool]],

      [:gvl, :per_thread, "a kernel routine's reentry and handoff flags, which hold only while that routine runs on this thread",
       %w[arity_raised builtin_raised raise_jumped backtrace_asking set_backtrace_calling warning_depth marshal_bailed
          uniform_failed preempt_busy trace_quiet trace_c_returning internal_running internal_arg imports_running
          meta_classes_busy unwarned_call_from class_new_refined const_for_program const_reflective direct_pending]],
      [:gvl, :per_thread, "a continuation's capture and its side context",
       %w[cont_mode cont_op cont_side_ctx cont_side_ready]],
      [:gvl, :per_thread, "the file that loads now, its hidden flag and a walked program's require",
       %w[loading hidden_loader walking]],
      [:gvl, :per_thread, "scratch rows that one search or one message uses at a time",
       %w[onig_scratch strerror errno inspect_index]],
      [:gvl, :per_thread, "the task the eval compiler runs on, so the program's frames stay its own",
       %w[eval_task]],

      [:gvl, :atomic, "a stamp that every inline cache compares; writers bump it",
       %w[const_stamp mcache_stamp site_stamp mcache_mode class_serial master_serial]],
      [:gvl, :atomic, "a counter that hands out ids",
       %w[object_id_counter box_slots]],

      [:gvl, :stopped, "the collector's state: it runs with every other thread at a safe point",
       %w[heap size_classes mark_stack marking full_word gc_profile alloc_trace mark_every]],
      [:gvl, :stopped, "the lists of fibers, weak references, finalizers and C roots that each collection reads and prunes",
       %w[fiber_list weak_list finalizer_queue data_frees unprotected c_root_addresses c_root_objects finalizing_at_exit]],

      [:gvl, :vm_lock, "the symbol table and its C names",
       %w[symtab capi_id_names]],
      [:gvl, :vm_lock, "global variables, their aliases, guesses, mirrors and trace_var commands",
       %w[gvars gvar_aliases gvar_guesses gvar_mirrors gvar_traced]],
      [:gvl, :vm_lock, "the method cache, the gates and their rows, and Refinement#import_methods' functions",
       %w[mcache gate_rows gates gates_taken ruby2_fns c_undef]],
      [:gvl, :vm_lock, "boxes' constant and class snapshots",
       %w[master_consts]],
      [:gvl, :vm_lock, "the globals table (G_*): each slot has an entry of its own below",
       %w[globals]],
      [:gvl, :vm_lock, "TracePoint, Coverage and internal event hooks: the enabled set, the points and the counters",
       %w[trace_events trace_points trace_built coverage coverage_evals coverage_main_ran coverage_branch_jumps coverage_oneshot
          internal_events internal_hooks thread_hooks profiled refined_procs]],
      [:gvl, :vm_lock, "the C API's lazily made tables: encodings, st views, Ractor keys, thread keys, cfuncs and Ractor safety",
       %w[capi_encodings capi_ready capi_vm_at_exit st_views ractor_c_keys thread_specific_keys unsafe_cfuncs ext_ractor_safe]],
      [:gvl, :vm_lock, "functions resolved once with dlsym; each store is the same word",
       %w[fdopen_fn getgroups_fn select_fn ffi_image ffi_call_fn ffi_closure_alloc_fn ffi_closure_free_fn ffi_prep_cif_fn
          ffi_prep_cif_var_fn ffi_prep_closure_loc_fn linux_symtab linux_jit_cursor]],
      [:gvl, :vm_lock, "settings that the core changes for the whole process",
       %w[backtrace_limit regexp_limit warn_deprecated path_index syslog_ident]],
      [:gvl, :vm_lock, "the IO globals and record separators that $stdout, $/, $; and $, set",
       %w[rb_stdin rb_stdout rb_stderr rb_rs rb_default_rs rb_fs rb_output_fs rb_output_rs]],
      [:gvl, :vm_lock, "the fiber pool's limit and count",
       %w[fiber_pool]],
      [:gvl, :vm_lock, "the timer thread starts once, with the receiver of its safe points",
       %w[poll_started preempt_mid preempt_to]],
      [:gvl, :immutable, "whether threads are native: ZR_THREADS, read at the first switch",
       %w[threads_mode]],
      [:gvl, :main, "the root fiber of the main thread, and whether the program has begun",
       %w[root_fiber program_started]],
      [:gvl, :main, "the count of each signal whose Ruby handler ran: only the main thread runs them",
       %w[signal_taken]],

      [:boot, :main, "the process's own stack, contexts, arguments and environment",
       %w[process_context program_context program_stack args_cell wasi_environ wasi_preopens]],
      [:boot, :immutable, "the main thread's Task; each other thread allocates its own",
       %w[task]],
      [:boot, :immutable, "frame metadata of the kernel's own frames",
       %w[anonymous_meta anonymous_meta1 capi_cblock_meta method_binding_meta]],
      [:boot, :immutable, "fixed values: the hash seed, the empty keyword table, st's hash types and memory size",
       %w[hash_seed kw_none st_objtype st_strcasetype st_strtype machine_bytes]],
      [:boot, :immutable, "the C API's data words: classes, modules, errors, Onigmo's tables, IO::Buffer's sizes, util.c's tables",
       %w[rb_cArray rb_cBasicObject rb_cBinding rb_cClass rb_cComplex rb_cDir rb_cEncoding rb_cEnumerator rb_cFalseClass rb_cFile
          rb_cFloat rb_cHash rb_cIO rb_cIOBuffer rb_cIOBufferSlice rb_cIOBufferStorage rb_cInteger rb_cMatch rb_cMethod rb_cModule
          rb_cNilClass rb_cNumeric rb_cObject rb_cProc rb_cRactor rb_cRandom rb_cRange rb_cRational rb_cRefinement rb_cRegexp
          rb_cSet rb_cStat rb_cString rb_cStruct rb_cSymbol rb_cThread rb_cTime rb_cTrueClass rb_cUnboundMethod
          rb_eArgError rb_eEOFError rb_eEncCompatError rb_eEncodingError rb_eException rb_eFatal rb_eFloatDomainError
          rb_eFrozenError rb_eIOError rb_eIOTimeoutError rb_eIndexError rb_eInterrupt rb_eKeyError rb_eLoadError
          rb_eLocalJumpError rb_eMathDomainError rb_eNameError rb_eNoMatchingPatternError rb_eNoMatchingPatternKeyError
          rb_eNoMemError rb_eNoMethodError rb_eNotImpError rb_eRangeError rb_eRegexpError rb_eRuntimeError rb_eScriptError
          rb_eSecurityError rb_eSignal rb_eStandardError rb_eStopIteration rb_eSyntaxError rb_eSysStackError
          rb_eSystemCallError rb_eSystemExit rb_eThreadError rb_eTypeError rb_eZeroDivError
          rb_mComparable rb_mEnumerable rb_mErrno rb_mFileTest rb_mGC rb_mKernel rb_mMath rb_mProcess rb_mWaitReadable
          rb_mWaitWritable OnigDefaultSyntax OnigEncodingASCII OnigEncodingUS_ASCII OnigEncodingUTF_8 OnigSyntaxRuby
          RUBY_IO_BUFFER_DEFAULT_SIZE RUBY_IO_BUFFER_MAP_ALIGNMENT RUBY_IO_BUFFER_PAGE_SIZE
          ruby_digit36_to_number_table ruby_hexdigits ruby_version zr_capi_debug zr_capi_verbose]],

      # The globals table, slot by slot.
      [:boot, :immutable, "a core class, module or object that the boot makes",
       %w[G_BASIC_OBJECT G_OBJECT G_MODULE G_CLASS G_KERNEL G_INTEGER G_STRING G_SYMBOL G_NIL G_TRUE G_FALSE G_MAIN G_RANGE
          G_NUMERIC G_EXCEPTION G_STANDARD_ERROR G_ARGUMENT_ERROR G_NAME_ERROR G_NO_METHOD_ERROR G_TYPE_ERROR
          G_ZERO_DIVISION_ERROR G_RUNTIME_ERROR G_TOP_CREF G_ARRAY G_INDEX_ERROR G_FROZEN_ERROR G_PROC G_LOCAL_JUMP_ERROR
          G_HASH G_KEY_ERROR G_METHOD G_UNBOUND_METHOD G_SYSTEM_STACK_ERROR G_FIBER G_FLOAT G_FATAL G_REGEXP G_REFINEMENT
          G_BOX G_NIL_TO_S G_TRUE_TO_S G_FALSE_TO_S G_START_DIR G_ARGV0 G_EMPTY_REST G_EMPTY_KWREST G_MATH_META]],
      [:gvl, :vm_lock, "a table that the program's definitions, requires and literals grow",
       %w[G_COVERAGE_METHODS G_AUTOLOAD_PROVIDED G_REGEXP_LITERALS G_FSTRINGS G_FSTRINGS_OTHER G_FINALIZERS G_ACTIVATIONS
          G_MASTER_GVARS G_HIDDEN_FEATURES G_RANGE_LITERALS G_FROZEN_LITERALS G_BIG_LITERALS G_REAL_FEATURES G_SYM_PROCS
          G_LOADING_FEATURES G_BLOCK_NAMES G_META_CLASSES G_VIS_COPIES G_AUTOLOADING G_SITE_METAS G_UNUSED_BLOCK_SITES
          G_DEBUG_STRINGS G_AUTOLOAD_READ G_USING_TOPLEVEL G_META_OWNERS]],
      [:gvl, :vm_lock, "ARGV and the at_exit list, which the program changes",
       %w[G_ARGV G_AT_EXIT]],
      [:gvl, :per_thread, "the callback and unwind state of a C call in progress",
       %w[G_FFI_CALLBACK G_FFI_UNWIND G_C_CALLBACK]]
    ].freeze #: Array[[Symbol, Symbol, String, Array[String]]]

    ENTRIES = ROWS.each_with_object({}) do |(now, free, note, names), entries|
      names.each { |name| entries[name] = Entry.new(now:, free:, note:) }
    end.freeze #: Hash[String, Entry]

    module_function

    #: (String | Symbol name) -> Entry?
    def [](name) = ENTRIES[name.to_s]

    # The names whose value each thread keeps for itself under the GVL:
    # what a GVL handoff saves and restores.
    #: () -> Array[String]
    def per_thread = ENTRIES.select { |_, entry| entry.now == :thread }.keys
  end
end
