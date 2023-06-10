use std::ffi;

extern crate noria;
extern crate tokio;
extern crate nom_sql;
#[macro_use]
extern crate lazy_static;
extern crate chrono;

use std::rc::Rc;
use std::collections::HashMap;

use std::os::raw::{c_double, c_char, c_longlong, c_int};

use noria::DataType;

pub struct Connection(noria::SyncControllerHandle<noria::LocalAuthority, tokio::runtime::TaskExecutor>);

pub struct Row(Vec<noria::DataType>, Schema);

pub struct QueryResult(std::vec::IntoIter<Vec<noria::DataType>>, Schema);

type Schema = Rc<HashMap<String, usize>>;

lazy_static! {
    // Actually excludes more things
    static ref EXCLUDE_FOREIGN_KEY_CONSTRAINTS : regex::Regex = 
        regex::Regex::new(r",\s*CONSTRAINT [\w`]+ FOREIGN KEY \([`\w]+\) REFERENCES [\w`]+ \([`\w]+\)|ON (:?DELETE|UPDATE) CASCADE|DEFAULT current_timestamp\(\)").unwrap();
}

fn new_schema(columns: &[String]) -> Schema {
    Rc::new(columns.iter().cloned().enumerate().map(|(a, b)| (b, a)).collect())
}


#[no_mangle]
pub unsafe extern "C" fn setup_connection(dat_file: *const c_char) -> Box<Connection> {
    let s = ffi::CStr::from_ptr(dat_file);
    let fname = s.to_str().unwrap();
    println!("Recieved filename {}", fname);
    let mut b = noria::Builder::default();
    b.disable_partial();
    if std::env::var("NORIA_LOGGIN").is_ok() {
        b.log_with(noria::logger_pls());
    }
    let handle = Box::leak(Box::new(b.start_simple().unwrap()));
    let out = handle.clone();
    {   
        use nom_sql::parser::*;
        let file = std::fs::File::open(fname).unwrap();
        let reader = std::io::BufReader::new(file);
        let mut errors = 0;
        use std::io::BufRead;
        reader.split(';' as u8).for_each(|v| {
            let owned_s = String::from_utf8(v.unwrap()).unwrap();
            let constraints_droped = EXCLUDE_FOREIGN_KEY_CONSTRAINTS.replace_all(&owned_s, "");
            let s = constraints_droped.trim();
            if s.starts_with("/*") || s.starts_with("SET") || s.is_empty() { return; }
            match parse_query(s) {
                Ok(SqlQuery::CreateTable(_)) => {
                    handle.extend_recipe(s).unwrap();
                }
                Ok(SqlQuery::Insert(i)) => {
                    let mut table = handle.table(i.table.name).unwrap().into_sync();
                    let r_len = table.columns().len();
                    let remapper = i.fields.map(|insert_cols| {
                        let actual_cols = table.columns();
                        assert_eq!(insert_cols.len(), actual_cols.len());
                        actual_cols.iter().map(|c|
                            if let Some((i, _)) = insert_cols.iter().enumerate().find(|(_, p)| &p.name == c) {
                                i
                            } else {
                                panic!("Could not find target column {c} in actual columns {actual_cols:?}");
                            }
                        ).collect::<Vec<_>>()
                    });
                    let batch = i.data.into_iter().map(|rec| {
                        assert_eq!(rec.len(), r_len);
                        noria::TableOperation::Insert(
                            (0..r_len).map(|i| {
                                let idx = if let Some(ref m) = remapper {
                                    m[i]
                                } else {
                                    i
                                };
                                (&rec[idx]).into()
                            }).collect()
                        )
                    });
                    table.perform_all(batch).unwrap();
                }
                Err(e) => {
                    errors += 1;
                    eprintln!("Unparseable query. Error: {}\n {:?}", e, s);
                }   
                Ok(_) => {
                    errors += 1;
                    eprintln!("Unhandled query {:?}", s);
                }
            }
        });
        assert_eq!(errors, 0);
    }
    Box::new(Connection(out))
}

#[no_mangle]
pub unsafe extern "C" fn install_query(conn: &mut Connection, query: *const c_char) {
    let qstr = ffi::CStr::from_ptr(query).to_str().unwrap();
    println!("Setting up new query {}", qstr);
    conn.0.extend_recipe(qstr).unwrap();
    dump_graph(conn);
}

fn dump_graph(conn: &mut Connection) {
    let mut gfile = std::fs::OpenOptions::new().truncate(true).create(true).write(true).open("noria-graph.gv").unwrap();
    use std::io::Write;
    write!(gfile, "{}", conn.0.graphviz().unwrap());
}

#[no_mangle]
pub unsafe extern "C" fn install_udf(conn: &mut Connection, udf: *const c_char) {
    conn.0.install_udtf(ffi::CStr::from_ptr(udf).to_str().unwrap(), false, &[]).unwrap();
    dump_graph(conn);
}

#[no_mangle]
pub extern "C" fn remove_view(view: *const c_char) {}

#[no_mangle]
pub unsafe extern "C" fn run_query0(conn: &mut Connection, q: *const c_char, key: c_longlong) -> Option<Box<QueryResult>> {
    let mut view = conn.0.view(ffi::CStr::from_ptr(q).to_str().unwrap()).unwrap().into_sync();
    let res = view.lookup(&[key.into()], true).unwrap();
    if res.len() == 0 {
        println!("No result found");
        None
    } else {
        println!("{} results found", res.len());
        Some(Box::new(QueryResult(res.into_iter(), new_schema(view.columns()))))
    }
}

#[no_mangle]
pub unsafe extern "C" fn free_query_result(_res: Option<Box<QueryResult>>) {}

#[no_mangle]
pub extern "C" fn next_row0(result: &mut QueryResult) -> Option<Box<Row>> {
    result.0.next().map(|i| Box::new(Row(i, result.1.clone())))
}

#[no_mangle]
pub extern "C" fn advance_result(result: &mut QueryResult, len: c_int) {
    for _ in 0..(len as usize) {
        result.0.next();
    }
}

#[no_mangle]
pub unsafe extern "C" fn free_row(_row: Option<Box<Row>>) {}

#[no_mangle]
pub unsafe extern "C" fn row_index(row: &Row, key: *const c_char) -> &DataType {
    let keystr = ffi::CStr::from_ptr(key).to_str().expect("Could not convert row key to rust string");
    let idx = row.1.get(keystr).unwrap_or_else(|| panic!("Key '{}' not found in schema. {:?}", keystr, row.1.keys()));
    &row.0.get(*idx).unwrap_or_else(|| panic!("Index {} (for key {}) not found in row.", idx, keystr))
}

#[no_mangle]
pub extern "C" fn datatype_to_int(dt: &DataType) -> c_longlong {
    dt.clone().into()
}

#[no_mangle]
pub extern "C" fn datatype_to_string(dt: &DataType) -> *mut c_char {
    let string : String = dt.clone().into();
    let cstring = ffi::CString::new(string).unwrap();
    cstring.into_raw()
}

#[no_mangle]
pub extern "C" fn datatype_to_float(dt: &DataType) -> c_double {
    dt.clone().into()
}

#[no_mangle]
pub extern "C" fn datatype_to_bool(dt: &DataType) -> bool {
    let i : i64 = dt.clone().into();
    i != 0
}

#[no_mangle]
pub extern "C" fn datatype_is_null(dt: &DataType) -> bool {
    dt.is_none()
}

#[no_mangle]
pub extern "C" fn datatype_to_timestamp(dt: &DataType) -> i64 {
    use chrono::naive::NaiveDateTime;
    match dt {
        DataType::Timestamp(ts) => ts.timestamp(),
        DataType::Text(t) => NaiveDateTime::parse_from_str(t.to_str().unwrap(), "%Y-%m-%d %H:%M:%S").unwrap().timestamp(),
        _ => dt.clone().into(),
    }
}