module Byebug::DAP
  module Scalar
    def ===(value)
      case value
      when nil, true, false
        return true
      when ::String, ::Symbol, ::Numeric
        return true
      when ::Time, ::Range
        true
      end

      return true if defined?(::Date) && ::Date === value
      return true if defined?(::DateTime) && ::DateTime === value

      false
    end
  end
end
