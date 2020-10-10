module Byebug::DAP
  class Command::Threads < Command
    # "The request retrieves a list of all threads.

    register!

    def execute
      started!

      respond! body: ::DAP::ThreadsResponseBody.new(
        threads: Byebug
          .contexts
          .filter { |ctx| !ctx.thread.is_a?(::Byebug::DebugThread) }
          .map { |ctx| ::DAP::Thread.new(
            id: ctx.thnum,
            name: ctx.thread.name || "Thread ##{ctx.thnum}"
          ).validate! })
    end
  end
end
