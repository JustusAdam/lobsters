use std::ffi;

#[repr(transparent)]
pub struct Connection;

#[no_mangle]
pub unsafe extern "C" fn setup_connection(dat_file: *const i8) -> *mut Connection {
    let s = ffi::CStr::from_ptr(dat_file);
    println!("Recieved filename {}", s.to_str().unwrap());
    let conn = Box::new(Connection);
    Box::leak(conn)
}