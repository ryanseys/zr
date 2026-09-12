# frozen_string_literal: true

# The IR: a CFG in SSA form with block parameters, restricted to the 47
# opcodes and the four types ze0 emits. Every lowering builds it and every
# backend reads it; nothing writes it as text.
require_relative "ir/function"
