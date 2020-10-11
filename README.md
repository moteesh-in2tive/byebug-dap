# Byebug Debug Adapter Protocol

This gem adds [Debug Adapter
Protocol](https://microsoft.github.io/debug-adapter-protocol) support to Byebug.

## TODO

- In STDIO mode, spawn with extra FDs and use those instead of 0/1?
- Set class-only or instance-only method breakpoints. Blocked by
  [byebug#734](https://github.com/deivid-rodriguez/byebug/issues/734).
- Support advanced exception breakpoints. Requires client support (VSCode
  extension).
