module NoriaInterface

  extend FFI::Library
  ffi_lib [FFI::CURRENT_PROCESS, "noria-interface/target/debug/libnoria_interface." + FFI::Platform::LIBSUFFIX]
  attach_function :setup_connection, [:string], :pointer
  attach_function :run_query, [:string], :pointer
  attach_function :next_row, [:pointer], :pointer
  attach_function :row_index, [:pointer, :string], :pointer
  attach_function :datatype_to_int, [:pointer], :int
  attach_function :datatype_to_string, [:pointer], :string
  attach_function :datatype_to_float, [:pointer], :double
  attach_function :datatype_to_bool, [:pointer], :bool
  attach_function :datatype_is_null, [:pointer], :bool
  attach_function :install_udf, [:pointer, :string], :void
  attach_function :install_query, [:pointer, :string], :void

  
end