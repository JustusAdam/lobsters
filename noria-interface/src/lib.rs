use std::ffi;

extern crate noria;
extern crate tokio;
extern crate nom_sql;

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
    let fname = s.to_str().unwrap();
    println!("Recieved filename {fname}");
    let mut b = noria::Builder::default();
    b.disable_partial();
    let conn = b.start_simple().unwrap();
    let out = conn.clone();
    {   
        use nom_sql::parser::*;
        let handle = conn.into_sync();
        let file = std::fs::File::open(fname).unwrap();
        let reader = std::io::BufReader::new(file);
        let mut errors = 0;
        reader.split(';').for_each(|v| {
            let s = v.unwrap();
            match parse_query_bytes(s) {
                Ok(SqlQuery::CreateTable(t)) => b.extend_recipe(s).unwrap();
                Ok(SqlQuery::Insert(i)) => {
                    let table = b.table(i.table).unwrap().into_sync();
                    let remapper = i.columns.map(|insert_cols| {
                        let actual_cols = table.columns();
                        assert_eq!(insert_cols.len(), actual_cols.len());
                        actual_cols.iter().map(|c|
                            if let Some((i, _)) = insert_cols.iter().enumerate().find(|(i, p)| p == c) {
                                i
                            } else {
                                panic!("Could not find target column {c} in actual columns {actual_cols:?}");
                            }
                        ).collect::<Vec<_>>()
                    });
                    let batch = i.data.into_iter().map(|rec| {
                        assert_eq!(rec.len(), actual_cols.len());
                        (0..actual_cols.len()).map(|i| {
                            let idx = if let Some(m) = remapper {
                                m[i]
                            } else {
                                i
                            };
                            noria::TableOperation::Insert((&rec[idx]).into())
                        })
                    });
                    table.perform_all(batch);
                }
                Err(e) => {
                    errors += 1;
                    eprintln!("Unparseable query {s}");
                }   
                Ok(_) => {
                    errors += 1;
                    eprintln!("Unhandled query {s}");
                }
            }
        });
    }
    Box::new(Connection(out))
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