# Test exception classes

class T_exceptions_AppError < RuntimeError
end

class T_exceptions_NotFoundError < T_exceptions_AppError
end

# Raise custom exception
begin
  raise T_exceptions_NotFoundError, "item not found"
rescue T_exceptions_NotFoundError => e
  puts e  # item not found
rescue T_exceptions_AppError => e
  puts "app error"
end

# Raise with class name
begin
  raise T_exceptions_AppError, "something went wrong"
rescue T_exceptions_NotFoundError => e
  puts "not found"
rescue T_exceptions_AppError => e
  puts e  # something went wrong
end

# Bare rescue catches all
begin
  raise "generic error"
rescue => e
  puts e  # generic error
end

puts "done"
