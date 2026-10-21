# frozen_string_literal: true

# `require "io/nonblock"`: O_NONBLOCK on the descriptor. ruby adds these
# methods at the require, so a program that never requires the feature
# does not have them.
class IO
  def nonblock? = nonblock_flag?

  def nonblock=(on)
    set_nonblock(on)
    on
  end

  # The flag for the length of a block, and then back as it was. CRuby's
  # reader form takes that block, so a call with none raises.
  def nonblock(*args)
    raise LocalJumpError, "no block given" unless block_given?

    was = nonblock_flag?
    set_nonblock(args.empty? ? true : args[0])
    begin
      yield
    ensure
      set_nonblock(was)
    end
  end
end
