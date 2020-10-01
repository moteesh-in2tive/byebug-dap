require 'socket'

class Byebug::Remote::Server
  def start_unix(path)
    return if @thread

    if wait_connection
      mutex = Mutex.new
      proceed = ConditionVariable.new
    end

    server = UNIXServer.new(path)

    yield if block_given?

    @thread = ::Byebug::DebugThread.new do
      while (session = server.accept)
        @main_loop.call(session)

        mutex.synchronize { proceed.signal } if wait_connection
      end
    end

    mutex.synchronize { proceed.wait(mutex) } if wait_connection
  end
end
