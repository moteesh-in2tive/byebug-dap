module Byebug::DAP
  # Used in case statements to identify scalar types.
  # @api private
  module Scalar
    # Match scalar values. {std:NilClass nil}, {std:TrueClass true},
    # {std:FalseClass false}, {std:String strings}, {std:Numeric numbers},
    # {std:Time times}, {std:Range ranges}, {std:date:Date dates}, and
    # {std:date:DateTime date-times} are considered scalars.
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
