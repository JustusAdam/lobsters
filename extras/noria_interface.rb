module NoriaInterface

  NORIA_CONNECTION = nil
  NORIA_CONNECTION_CREATED = false

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

  def get_handle 
    unless NORIA_CONNECTION_CREATED
      dbcfg = Rails.configuration.database_configuration[Rails.env]
      Tempfile.create('test-db-dump.sql') do |tempfile|
        puts "dumping database to temporary file #{tempfile.path}"
        dbargs = []
        add_arg = ->(name, arg) { dbargs.push(arg, dbcfg[name]) unless dbcfg[name].nil? }
        add_arg.call("host", "--host")
        add_arg.call("port", "--port")
        add_arg.call("socket", "--socket")
        puts "Using conf parameters #{dbargs}"

        system "mariadb-dump", "--skip-create-options", "--compact", dbcfg["database"], *dbargs, 1=>tempfile.path
        puts "Dump filled the file with #{tempfile.size} bytes"
        NORIA_CONNECTION = NoriaInterface.setup_connection tempfile.path
        NoriaInterface.install_udf NORIA_CONNECTION, COMMENTS_QUERY
        # NoriaInterface.install_udf NORIA_CONNECTION, HIDDEN_STORIES_QUERY
        # NoriaInterface.install_query NORIA_CONNECTION, "VIEW #{FETCH_HIDDEN_Q}: SELECT * FROM #{HIDDEN_STORIES_QUERY} WHERE uid = ?"
        NORIA_CONNECTION_CREATED = true
      end
    end
    NORIA_CONNECTION
  end
end