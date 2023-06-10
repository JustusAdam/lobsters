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
  attach_function :remove_view, [:string], :void
  attach_function :advance_result, [:pointer, :int], :void
  attach_function :datatype_to_timestamp, [:pointer], :long_long

  class Row 
    def initialize(r)
      @row = r
    end

    def index(field)
      NoriaInterface.row_index(@row, field)
    end

    def int(field)
      v = index(field)
      NoriaInterface.datatype_to_int(v) unless NoriaInterface.datatype_is_null(v)
    end

    def string(field)
      v = index(field)
      NoriaInterface.datatype_to_string(v).encode(Encoding::UTF_8) unless NoriaInterface.datatype_is_null(v)
    end

    def float(field)
      i = index(field)
      NoriaInterface.datatype_to_float(i) unless NoriaInterface.datatype_is_null(i)
    end

    def bool(field)
      v = index(field)
      NoriaInterface.datatype_to_bool(v) unless NoriaInterface.datatype_is_null(v)
    end

    def time(field)
      v = index(field)
      Time.at(NoriaInterface.datatype_to_timestamp(v)) unless NoriaInterface.datatype_is_null(v)
    end
  end

  def self.next_row(ptr) 
    ptr = FFI::AutoPointer.new(next_row0(ptr), method(:free_row))
    Row.new(ptr) unless ptr.null?
  end

  def self.run_query(ptr, str, int)
    FFI::AutoPointer.new(run_query0(ptr, str, int), method(:free_query_result))
  end
end