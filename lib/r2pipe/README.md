# `lib/r2pipe`

`r2pipe.hc` is a synchronous AHolyC client for radare2. It supports a spawned
`radare2 -q0` process, inherited `R2PIPE_IN`/`R2PIPE_OUT` file descriptors,
and r2 web servers over HTTP or HTTPS. All features are enabled by default;
set a feature define to `0` before inclusion to minimize the binary:

```c
#define R2PIPE_USE_SPAWN 0
#define R2PIPE_USE_FDS 1
#define R2PIPE_USE_HTTP 0
#define R2PIPE_USE_JSON 0
#include "lib/r2pipe/r2pipe.hc"
```

`R2PIPE_USE_SPAWN` omits process support, `R2PIPE_USE_FDS` omits inherited
descriptor support, `R2PIPE_USE_HTTP` omits HTTP(S), and `R2PIPE_USE_JSON`
omits JSON decoding and r2pipe2 helpers.

```c
#include "lib/r2pipe/r2pipe.hc"

CR2Pipe r2;
if (R2PipeOpen(&r2, "/bin/ls")) {
  "info: %s", R2PipeCmd(&r2, "ij");
  if (R2PipeCmdJ(&r2, "ij"))
    "JSON root type: %d\\n", r2.json.type;
  R2PipeClose(&r2);
}
```

`R2PipeSpawn(&r2, "radare2 -q0 -AA /bin/ls")` accepts a full command line.
`R2PipeOpenEnv(&r2)` uses r2's `R2PIPE_IN` and `R2PIPE_OUT`; the explicit
`R2PipeOpenFds(&r2, input, output)` form is available on Unix. These FDs are
borrowed and are not closed by `R2PipeClose`.

Pass `http://127.0.0.1:9090` to `R2PipeOpen` for a web server; commands are
POSTed as `text/plain` bodies to `/cmd`.

`R2PipeCmd` returns plain output. `R2PipeCmdJ` decodes it into `r2.json`.
`R2PipeCall`/`R2PipeCallJ` send a complete r2pipe2 JSON request, while
`R2PipeCmd2`/`R2PipeCmd2J` make `{"cmd":...}` requests (the `J` form asks for
a JSON result). On failure, the functions return `NULL`/`FALSE` and set
`r2.error`.
