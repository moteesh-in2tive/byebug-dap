module Byebug
  module DAP
    class InvalidRequestArgumentError
      attr_accessor :error, :value, :scope

      def initialize(error, value: nil, scope: nil)
        @error = error
        @value = value
        @scope = scope
      end
    end
  end
end
