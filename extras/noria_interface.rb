module NoriaInterface
  extend FFI::Library
  ffi_lib "noria-interface/target/debug/libnoria_interface." + FFI::Platform::LIBSUFFIX
  attach_function :setup_connection, [:string], :pointer
end