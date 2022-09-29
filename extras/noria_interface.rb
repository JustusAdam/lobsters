module NoriaInterface

  extend FFI::Library
  ffi_lib [FFI::CURRENT_PROCESS, "noria-interface/target/debug/libnoria_interface." + FFI::Platform::LIBSUFFIX]
  attach_function :setup_connection, [:string], :pointer
  attach_function :run_query0, [:pointer, :string, :long_long], :pointer
  attach_function :next_row0, [:pointer], :pointer
  attach_function :row_index, [:pointer, :string], :pointer
  attach_function :datatype_to_int, [:pointer], :long_long
  attach_function :datatype_to_string, [:pointer], :string
  attach_function :datatype_to_float, [:pointer], :double
  attach_function :datatype_to_bool, [:pointer], :bool
  attach_function :datatype_is_null, [:pointer], :bool
  attach_function :install_udf, [:pointer, :string], :void
  attach_function :install_query, [:pointer, :string], :void
  attach_function :free_row, [:pointer], :void
  attach_function :free_query_result, [:pointer], :void

  def self.next_row(ptr) 
    FFI::AutoPointer.new(next_row0(ptr), method(:free_row))
  end

  def self.run_query(ptr, str, int)
    FFI::AutoPointer.new(run_query0(ptr, str, int), method(:free_query_result))
  end
end