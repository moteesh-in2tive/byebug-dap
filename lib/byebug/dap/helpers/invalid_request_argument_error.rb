module Byebug
  module DAP
    # Raised when the client sends a request with invalid arguments
    # @api private
    class InvalidRequestArgumentError < StandardError
      # The error kind or message.
      # @return [std:Symbol|std:String]
      attr_reader :error

      # The error value.
      attr_reader :value

      # The error scope.
      attr_reader :scope

      def initialize(error, value: nil, scope: nil)
        @error = error
        @value = value
        @scope = scope
      end
    end
  end
end
