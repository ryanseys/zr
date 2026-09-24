# frozen_string_literal: true

# The IR: a CFG in SSA form with block parameters, restricted to the 54
# opcodes and the four types zr emits. Lowering builds it and each
# backend reads it. zr never writes it as text.
require_relative "ir/function"
require_relative "ir/mem2reg"
