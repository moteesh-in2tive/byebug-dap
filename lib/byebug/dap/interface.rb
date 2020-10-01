module Byebug
  module DAP
    class Interface
      attr_reader :socket

      def initialize(socket)
        @socket = socket
      end

      def puts(message)
        socket.write ::DAP::Encoding.encode(message)
      end

      def gets
        ::DAP::Encoding.decode(socket)
      end

      def stack_frames
        @stack_frames ||= Handles.new
      end

      def variable_scopes
        @variable_scopes ||= Handles.new
      end
    end
  end
end
