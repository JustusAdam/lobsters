use std::ffi;

extern crate noria;
extern crate tokio;

#[repr(transparent)]
pub struct Connection(noria::SyncControllerHandle<noria::LocalAuthority, tokio::runtime::TaskExecutor>);

#[repr(transparent)]
pub struct Row(Vec<noria::DataType>);

#[repr(transparent)]
pub struct QueryResult(std::vec::IntoIter<Vec<noria::DataType>>);

#[no_mangle]
pub unsafe extern "C" fn setup_connection(dat_file: *const std::os::raw::c_char) -> Box<Connection> {
    let s = ffi::CStr::from_ptr(dat_file);
    println!("Recieved filename {}", s.to_str().unwrap());
    let mut b = noria::Builder::default();
    b.disable_partial();
    Box::new(Connection(b.start_simple().unwrap().clone()))
}

#[no_mangle]
pub unsafe extern "C" fn run_query(mut conn: Box<Connection>, q: *const std::os::raw::c_char, key: std::os::raw::c_int) -> Box<QueryResult> {
    let res = conn.0.view(ffi::CStr::from_ptr(q).to_str().unwrap()).unwrap().into_sync().lookup(&[key.into()], true).unwrap();
    Box::new(QueryResult(res.into_iter()))
}

#[no_mangle]
pub extern "C" fn next_row(mut result: Box<QueryResult>) -> Option<Box<Row>> {
    result.0.next().map(|i| Box::new(Row(i)))
}

#[no_mangle]
pub unsafe extern "C" fn result_get_int(row: Box<Row>) -> std::os::raw::c_int {
    0
}