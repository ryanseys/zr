# `JSON.parse` keeps an integer beyond a double's precision EXACT (a
# Bignum); a naive numeric parser converts it to Float and silently
# loses precision -- wrong DATA, the sharpest kind. (Found by the
# 2026-08-24 probe sweep.)
require "json"
p JSON.parse('{"x":123456789012345678901234567890}')["x"]
p JSON.parse("[9007199254740993]").first
