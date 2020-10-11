# Change Log

## Upcoming

- Support for output capture
- Support for setting function breakpoints
- Support for breakpoint locations request
- Support for delayed stack trace loading
- Basic support for exception breakpoints

## 0.1.2

- Fix possible failure when a breakpoint is hit but can't be resolved
- Fix possible failure when frame arguments can't be evaluated
- Exit on disconnect when started by 'launch'
- Expose `Byebug::DAP::Server#wait_for_client` instead of passing a block
- Expose `Byebug::DAP#stop!` to allow the debugee to stop
- Support for specifying a start sequence with `--on-start CODE`
- Support for child processes

## 0.1.1

- Improve error handling in `Byebug::DAP::Controller`

## 0.1.0

- Initial release
