module Byebug::DAP
  # Used in case statements to identify scalar types.
  # @api private
  module Scalar
    # Match scalar values. Scalars are `nil`, `true`, `false`, {String},
    # {Symbol}, {Numeric}, {Time}, {Range}, {Date}, {DateTime}.
    # @return [Boolean]
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
