# Exceptions cross the boundary as plain references: a box-defined
# `BoxError < StandardError` raised from box code is rescuable in main
# through the SHARED bootstrap superclass chain, and `e.class` names it.



require_relative "box_exceptions/main"
