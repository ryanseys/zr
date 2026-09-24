# frozen_string_literal: true

# The IR: a CFG in SSA form with block parameters, restricted to the 54
# opcodes and the four types zr emits. Every lowering builds it and every
# backend reads it; nothing writes it as text.
require_relative "ir/function"
require_relative "ir/mem2reg"
