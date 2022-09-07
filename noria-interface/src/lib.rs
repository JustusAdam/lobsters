use std::ffi;

extern crate noria;
extern crate tokio;

use std::rc::Rc;
use std::collections::HashMap;

use std::os::raw::{c_int, c_char};

pub struct Connection(noria::SyncControllerHandle<noria::LocalAuthority, tokio::runtime::TaskExecutor>);

pub struct Row(Vec<noria::DataType>, Schema);

pub struct QueryResult(std::vec::IntoIter<Vec<noria::DataType>>, Schema);

type Schema = Rc<HashMap<String, usize>>;

fn new_schema(columns: &[String]) -> Schema {
    Rc::new(columns.iter().cloned().enumerate().map(|(a, b)| (b, a)).collect())
}

#[no_mangle]
pub unsafe extern "C" fn setup_connection(dat_file: *const c_char) -> Box<Connection> {
    let s = ffi::CStr::from_ptr(dat_file);
    println!("Recieved filename {}", s.to_str().unwrap());
    let mut b = noria::Builder::default();
    b.disable_partial();
    Box::new(Connection(b.start_simple().unwrap().clone()))
}

#[no_mangle]
pub unsafe extern "C" fn run_query(conn: &mut Connection, q: *const c_char, key: c_int) -> Box<QueryResult> {
    let mut view = conn.0.view(ffi::CStr::from_ptr(q).to_str().unwrap()).unwrap().into_sync();
    let res = view.lookup(&[key.into()], true).unwrap();
    Box::new(QueryResult(res.into_iter(), new_schema(view.columns())))
}

#[no_mangle]
pub extern "C" fn next_row(result: &mut QueryResult) -> Option<Box<Row>> {
    result.0.next().map(|i| Box::new(Row(i, result.1.clone())))
}

#[no_mangle]
pub unsafe extern "C" fn row_get_int(row: &Row, key: *const c_char) -> c_int {
    row.0[row.1[ffi::CStr::from_ptr(key).to_str().unwrap()]].clone().into()
}

#[no_mangle]
pub unsafe extern "C" fn row_get_string(row: &Row, key: *const c_char) -> *mut c_char {
    let string : String = row.0[row.1[ffi::CStr::from_ptr(key).to_str().unwrap()]].clone().into();
    let cstring = ffi::CString::new(string).unwrap();
    cstring.into_raw()
}