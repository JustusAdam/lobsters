module NoriaInterface
  extend FFI::Library
  ffi_lib "noria-interface/target/debug/libnoria_interface." + FFI::Platform::LIBSUFFIX
  attach_function :setup_connection, [:string], :pointer
  attach_function :run_query, [:string], :pointer
  attach_function :next_row, [:pointer], :pointer
  attach_function :row_get_int, [:pointer, :string], :int
  attach_function :row_get_string, [:pointer, :string], :string
  attach_function :install_udf, [:pointer, :string], :void
  attach_function :install_query, [:pointer, :string], :void
end