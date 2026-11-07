//! The watchdog's "is the main app answering?" probe: one HTTP/1.0 GET with a timeout. http:// only,
//! since the app runs on localhost (deviation D5). Status 400 or higher counts as not answering, as
//! it did with board.py's urllib.

use std::io::{Read, Write};
use std::net::{TcpStream, ToSocketAddrs};
use std::time::Duration;

pub fn probe(url: &str, timeout: Duration) -> Result<(), String> {
    let rest = url
        .strip_prefix("http://")
        .ok_or_else(|| "only http:// URLs are supported".to_string())?;
    let (host, path) = match rest.find('/') {
        Some(i) => (&rest[..i], &rest[i..]),
        None => (rest, "/"),
    };
    if host.is_empty() {
        return Err("no host in the URL".to_string());
    }
    let has_port = host
        .rsplit_once(':')
        .is_some_and(|(_, p)| p.parse::<u16>().is_ok());
    let target = if has_port {
        host.to_string()
    } else {
        format!("{host}:80")
    };
    // try every address, as urllib did: "localhost" may resolve to ::1 first while the app listens on 127.0.0.1
    let mut last = format!("cannot resolve {host}");
    let mut stream = None;
    for addr in target.to_socket_addrs().map_err(|e| e.to_string())? {
        match TcpStream::connect_timeout(&addr, timeout) {
            Ok(s) => {
                stream = Some(s);
                break;
            }
            Err(e) => last = e.to_string(),
        }
    }
    let mut stream = stream.ok_or(last)?;
    stream
        .set_read_timeout(Some(timeout))
        .map_err(|e| e.to_string())?;
    stream
        .set_write_timeout(Some(timeout))
        .map_err(|e| e.to_string())?;
    // one write: `write!` on a TcpStream sends each format piece separately, and a server that answers
    // on its first read would see "GET " alone, reply, close, and the next piece would fail with EPIPE
    let request = format!("GET {path} HTTP/1.0\r\nHost: {host}\r\nConnection: close\r\n\r\n");
    stream
        .write_all(request.as_bytes())
        .map_err(|e| e.to_string())?;
    let mut head = [0u8; 64];
    let n = stream.read(&mut head).map_err(|e| e.to_string())?;
    let status = String::from_utf8_lossy(&head[..n])
        .split_whitespace()
        .nth(1)
        .and_then(|c| c.parse::<u16>().ok())
        .ok_or_else(|| "no HTTP status line in the reply".to_string())?;
    if status >= 400 {
        Err(format!("HTTP Error {status}"))
    } else {
        Ok(())
    }
}
