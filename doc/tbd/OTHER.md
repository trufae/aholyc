# AholyC TODO

* -fno-pic
* -fno-inline
* -fno-exceptions
* -os netbsd crosscompilation .. or '-target triplet' like zig cc does?

* Linking visibility
  * Used in TempleOS `extern` / `_extern` / `_intern` / `public`
  * default/hidden/internal/protected/private/public/

* naked functions? maybe /* @naked */ ?
* integer overflows
  * @pointer -> force bits to pc size or maybe @bits=*
  * @checked
  * @align
  * @clamp
  * @checked

* 32bit support
  * see m32 branch, ugly stuff around, but worth checking and discussing if needed
