# frozen_string_literal: true

module Ze0
  # `case/in`, `expr in pattern` and `expr => pattern`: ruby's pattern
  # matching, lowered as branching control flow.
  #
  # A pattern is a chain of sub-checks over ONE shared failure block. Each
  # check jumps there on a mismatch and falls through on a match, so a
  # pattern matches exactly when it reaches the end without jumping. A
  # binding is a side effect along the way and survives a later check's
  # failure, as ruby's does.
  #
  # Every leaf test and every failure record is a runtime call, so a
  # compiled `NoMatchingPatternError` cannot drift from the one the
  # runtime raises.
  module Patterns
    # `case subject; in ...; end`. The subject is evaluated ONCE and
    # borrowed by every arm.
    def lower_case_match(node)
      subject = borrow(lower_expr(node.predicate))
      # Only the shape that READS a key miss pays to clear the record.
      single = node.conditions.size == 1
      f.call(f.import("zeo_rt_pat_key_miss_clear")) if single
      result = f.slot
      store_nil(addr_of(result))
      done = f.label
      node.conditions.each do |condition|
        missed = f.label
        lower_arm(condition, subject, missed)
        arm(lower_statements(condition.statements), result, done)
        f.switch(missed)
      end
      no_arm_matched(node, subject, result, done, single)
      f.switch(done)
      Operand.new(result, true, false)
    end

    # `expr in pattern`: a boolean one-liner that never raises. What a
    # successful match bound still reaches the scope around it.
    def lower_match_predicate(node)
      subject = borrow(lower_expr(node.value))
      result = f.slot
      missed, done = f.label, f.label
      match_pattern(node.pattern, subject, missed)
      move(literal_bool(1), addr_of(result))
      f.jump(done)
      f.switch(missed)
      move(literal_bool(0), addr_of(result))
      f.jump(done)
      f.switch(done)
      Operand.new(result, true, false)
    end

    # `expr => pattern`: the same match, raising instead of answering
    # false. Its own value is nil.
    def lower_match_required(node)
      subject = borrow(lower_expr(node.value))
      f.call(f.import("zeo_rt_pat_key_miss_clear"))
      missed, done = f.label, f.label
      match_pattern(node.pattern, subject, missed)
      f.jump(done)
      f.switch(missed)
      status_check(f.call_val(f.import("zeo_rt_pat_match_error"), [subject]))
      f.jump(done)
      f.switch(done)
      literal_nil
    end

    private

    # One `in` clause. Prism wraps a guarded pattern in the `if` or
    # `unless` that guards it, so the pattern is that node's statement.
    def lower_arm(condition, subject, missed)
      pattern = condition.pattern
      case pattern
      when Prism::IfNode, Prism::UnlessNode
        match_pattern(pattern.statements.body.first, subject, missed)
        check_guard(pattern.predicate, pattern.is_a?(Prism::UnlessNode), missed)
      else match_pattern(pattern, subject, missed)
      end
    end

    # A guard that rejects is its own reason: the pattern matched and the
    # condition did not.
    def check_guard(predicate, negated, missed)
      truth = truthy(lower_expr(predicate))
      held, rejected = f.label, f.label
      f.brif(truth, negated ? rejected : held, negated ? held : rejected)
      f.switch(rejected)
      f.call(f.import("zeo_rt_pat_fail_guard"))
      f.jump(missed)
      f.switch(held)
    end

    # Every arm rejected: the `else`, or ruby's own error. With several
    # clauses ruby names only the subject -- no single failing sub-test
    # describes a match that had branches to try.
    def no_arm_matched(node, subject, result, done, single)
      return arm(lower_statements(node.else_clause.statements), result, done) if node.else_clause

      verb = single ? "zeo_rt_pat_match_error" : "zeo_rt_pat_match_error_bare"
      status_check(f.call_val(f.import(verb), [subject]))
      f.jump(done)
    end

    # `pattern`'s checks against the value at `scrut`: a mismatch jumps to
    # `missed`, a match falls through.
    def match_pattern(pattern, scrut, missed)
      case pattern
      # A bare identifier always matches, binding the scrutinee.
      when Prism::LocalVariableTargetNode then bind_pattern(pattern, scrut)
      # `in (A | B)`: the parentheses group a PATTERN, not statements, so
      # prism keeps the one inside.
      when Prism::ParenthesesNode then match_pattern(pattern.body, scrut, missed)
      when Prism::AlternationPatternNode then alternation(pattern, scrut, missed)
      when Prism::CapturePatternNode
        match_pattern(pattern.value, scrut, missed)
        bind_pattern(pattern.target, scrut)
      when Prism::ArrayPatternNode then array_pattern(pattern, scrut, missed)
      when Prism::FindPatternNode then find_pattern(pattern, scrut, missed)
      when Prism::HashPatternNode then hash_pattern(pattern, scrut, missed)
      when Prism::PinnedVariableNode then case_eq_check(borrow(lower_expr(pattern.variable)), scrut, missed)
      when Prism::PinnedExpressionNode then case_eq_check(borrow(lower_expr(pattern.expression)), scrut, missed)
      # Every other pattern is a VALUE, matched by `===` -- the protocol
      # `case/when` uses, so `in` and `when` cannot drift apart. A class
      # name is a value like any other, and its `===` is `is_a?`.
      else case_eq_check(borrow(lower_expr(pattern)), scrut, missed)
      end
    end

    def bind_pattern(target, scrut)
      store_local(local(target), Operand.new(scrut, false, false))
    end

    # `P1 | P2`: the first alternative that matches wins. Ruby forbids an
    # alternative from binding, so nothing escapes a failed one.
    def alternation(pattern, scrut, missed)
      hit = f.label
      [pattern.left, pattern.right].each do |side|
        other = f.label
        match_pattern(side, scrut, other)
        f.jump(hit)
        f.switch(other)
      end
      f.jump(missed)
      f.switch(hit)
    end

    # `pat === scrut`, recording `P === v does not return true` when it
    # rejects. Every leaf pattern comes here.
    def case_eq_check(pat, scrut, missed)
      answer = f.slot
      status_check(f.call_val(f.import("zeo_rt_case_eq"), [pat, scrut, addr_of(answer)]))
      matched = f.fetch("i8", addr_of(answer))
      held, rejected = f.label, f.label
      f.brif(matched, held, rejected)
      f.switch(rejected)
      f.call(f.import("zeo_rt_pat_fail_case_eq"), [pat, scrut])
      f.jump(missed)
      f.switch(held)
    end

    # An Array/Hash/Find pattern's optional constant guard.
    def constant_guard(pattern, scrut, missed)
      return unless pattern.constant

      case_eq_check(borrow(lower_expr(pattern.constant)), scrut, missed)
    end

    # `[pre.., *rest, post..]`: `#deconstruct`, a length check, then the
    # element sub-patterns.
    def array_pattern(pattern, scrut, missed)
      constant_guard(pattern, scrut, missed)
      array = deconstruct(scrut, missed)
      length = f.call_val(f.import("zeo_rt_pat_array_len"), [array])
      pre, post = pattern.requireds, pattern.posts
      open = !pattern.rest.nil?
      check_length(array, length, pre.size + post.size, open, missed)
      pre.each_with_index { |p, i| match_pattern(p, array_elem(array, f.iconst("i64", i)), missed) }
      post.each_with_index do |p, i|
        at = f.isub(length, f.iconst("i64", post.size - i))
        match_pattern(p, array_elem(array, at), missed)
      end
      # An `[a,]` trailing comma is prism's `ImplicitRestNode`: it opens
      # the length but binds nothing.
      return unless pattern.rest.is_a?(Prism::SplatNode) && pattern.rest.expression

      to = f.isub(length, f.iconst("i64", post.size))
      bind_slice(pattern.rest.expression, array, f.iconst("i64", pre.size), to)
    end

    # A pattern with a `*` takes at least what it names; one without takes
    # exactly that. The mismatch names the DECONSTRUCTED array, not the
    # subject.
    def check_length(array, length, least, open, missed)
      fits = f.icmp(open ? "uge" : "eq", length, f.iconst("i64", least))
      held, wrong = f.label, f.label
      f.brif(fits, held, wrong)
      f.switch(wrong)
      f.call(f.import("zeo_rt_pat_fail_length"), [array, f.iconst("i64", least), f.iconst("i8", open ? 1 : 0)])
      f.jump(missed)
      f.switch(held)
    end

    # `[*, mid.., *]`: `mid` must match SOME window, searched left to
    # right, the first hit winning. A run-time loop by nature.
    def find_pattern(pattern, scrut, missed)
      constant_guard(pattern, scrut, missed)
      array = deconstruct(scrut, missed)
      length = f.call_val(f.import("zeo_rt_pat_array_len"), [array])
      mid = pattern.requireds
      width = f.iconst("i64", mid.size)
      start = f.slot
      head, body, none, hit = f.label, f.label, f.label, f.label
      f.store(f.iconst("i64", 0), addr_of(start))
      f.brif(f.icmp("uge", length, width), head, none)

      f.switch(none)
      f.call(f.import("zeo_rt_pat_fail_find"), [array])
      f.jump(missed)

      f.switch(head)
      at = f.fetch("i64", addr_of(start))
      last = f.isub(length, width)
      f.brif(f.icmp("ule", at, last), body, none)

      f.switch(body)
      step = f.label
      mid.each_with_index do |p, i|
        idx = i.zero? ? at : f.iadd(at, f.iconst("i64", i))
        match_pattern(p, array_elem(array, idx), step)
      end
      f.jump(hit)
      f.switch(step)
      f.store(f.iadd(at, f.iconst("i64", 1)), addr_of(start))
      f.jump(head)

      f.switch(hit)
      bind_slice(pattern.left.expression, array, f.iconst("i64", 0), at) if pattern.left.expression
      return unless pattern.right.expression

      bind_slice(pattern.right.expression, array, f.iadd(at, width), length)
    end

    # `{key: pattern, ..., **rest}`: `#deconstruct_keys`, then per-key
    # presence and value checks.
    def hash_pattern(pattern, scrut, missed)
      constant_guard(pattern, scrut, missed)
      keys = pattern.elements.map { |pair| hash_pattern_key(pair) }
      # CRuby passes the NAMED keys, and nil for a pattern that can take
      # everything: one with a rest, or with no keys at all.
      named = pattern.rest.nil? && !keys.empty? ? keys : []
      hash = deconstruct_keys(scrut, named, missed)
      check_hash_size(pattern, hash, keys, missed)
      pattern.elements.zip(keys) { |pair, key| hash_pair(pair, key, hash, missed) }
      rest = pattern.rest
      return unless rest.is_a?(Prism::AssocSplatNode) && rest.value

      store_local(local(rest.value), Operand.new(hash_except(hash, keys), false, false))
    end

    # A hash pattern names its keys with plain Symbols; a `"str":` key is
    # ruby's own syntax error inside one.
    def hash_pattern_key(pair)
      unless pair.key.is_a?(Prism::SymbolNode)
        raise Unsupported.new(pair.key, "a hash pattern key of that shape")
      end

      pair.key.unescaped
    end

    # `in {}` asks for an EMPTY hash -- ruby's one exception to hash
    # leniency -- and `**nil` asks that nothing else remain, which ruby
    # words differently because it names the LEFTOVERS.
    def check_hash_size(pattern, hash, keys, missed)
      empty = keys.empty? && pattern.rest.nil?
      no_more = pattern.rest.is_a?(Prism::NoKeywordsParameterNode)
      return unless empty || no_more

      size = f.call_val(f.import("zeo_rt_pat_hash_len"), [hash])
      exact = f.icmp("eq", size, f.iconst("i64", empty ? 0 : keys.size))
      held, wrong = f.label, f.label
      f.brif(exact, held, wrong)
      f.switch(wrong)
      if no_more && !keys.empty?
        f.call(f.import("zeo_rt_pat_fail_not_empty"), [hash_except(hash, keys), f.iconst("i8", 1)])
      else
        f.call(f.import("zeo_rt_pat_fail_not_empty"), [hash, f.iconst("i8", 0)])
      end
      f.jump(missed)
      f.switch(held)
    end

    # One `key: pattern` pair. A MISSING key is ruby's
    # NoMatchingPatternKeyError; a key that IS there with a value the
    # pattern rejects is the plain parent error, so only this records
    # itself.
    def hash_pair(pair, key, hash, missed)
      sym = sym_id(key)
      present = f.call_val(f.import("zeo_rt_pat_hash_has_key"), [hash, sym])
      held, absent = f.label, f.label
      f.brif(present, held, absent)
      f.switch(absent)
      f.call(f.import("zeo_rt_pat_key_miss_record"), [sym, hash])
      f.jump(missed)
      f.switch(held)

      value = f.slot
      f.call(f.import("zeo_rt_pat_hash_get"), [hash, sym, addr_of(value)])
      at = borrow(Operand.new(value, true, false))
      # `{key:}` shorthand binds a local of that name directly.
      return store_local(locals.fetch(key.to_sym), Operand.new(at, false, false)) if pair.value.is_a?(Prism::ImplicitNode)

      match_pattern(pair.value, at, missed)
    end

    # Everything the pattern did not name, as a new pooled Hash.
    def hash_except(hash, keys)
      names, count = cid_array(keys.map { |k| sym_id(k) })
      slot = f.slot
      f.call(f.import("zeo_rt_pat_hash_except"), [hash, names, count, addr_of(slot)])
      borrow(Operand.new(slot, true, false))
    end

    # `#deconstruct` and `#deconstruct_keys`: an Array or Hash is itself,
    # a value answering the protocol is asked, and anything else simply
    # does not match. What comes back is a fresh reference the frame pool
    # owns; every sub-pattern only borrows it.
    def deconstruct(scrut, missed)
      slot, matched = f.slot, f.slot
      status_check(f.call_val(f.import("zeo_rt_pat_deconstruct"), [scrut, addr_of(slot), addr_of(matched)]))
      deconstructed(slot, matched, missed)
    end

    def deconstruct_keys(scrut, keys, missed)
      # A NULL pointer is CRuby's `nil`: what it hands a pattern that can
      # take everything, and what such a `deconstruct_keys` reads.
      names, count = keys.empty? ? [f.iconst("i64", 0), f.iconst("i64", 0)] : cid_array(keys.map { |k| sym_id(k) })
      slot, matched = f.slot, f.slot
      status_check(f.call_val(
        f.import("zeo_rt_pat_deconstruct_keys"),
        [scrut, names, count, addr_of(slot), addr_of(matched)],
      ))
      deconstructed(slot, matched, missed)
    end

    def deconstructed(slot, matched, missed)
      held = f.label
      f.brif(f.fetch("i8", addr_of(matched)), held, missed)
      f.switch(held)
      borrow(Operand.new(slot, true, false))
    end

    # One element of the deconstructed array, in a pooled slot.
    def array_elem(array, index)
      slot = f.slot
      f.call(f.import("zeo_rt_pat_array_get"), [array, index, addr_of(slot)])
      borrow(Operand.new(slot, true, false))
    end

    # `array[from...to]` bound to a local: what an array or find pattern's
    # `*` names.
    def bind_slice(target, array, from, to)
      slot = f.slot
      f.call(f.import("zeo_rt_pat_array_slice"), [array, from, to, addr_of(slot)])
      store_local(local(target), Operand.new(borrow(Operand.new(slot, true, false)), false, false))
    end
  end
end
