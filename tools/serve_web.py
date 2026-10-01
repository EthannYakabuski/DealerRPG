"""Serve the generated Godot web build on localhost with WebAssembly MIME types."""

import argparse
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


class WebBuildHandler(SimpleHTTPRequestHandler):
    extensions_map = {
        **SimpleHTTPRequestHandler.extensions_map,
        ".wasm": "application/wasm",
        ".pck": "application/octet-stream",
        ".js": "application/javascript",
    }

    def end_headers(self):
        # Local iterations should always load the latest exported build.
        self.send_header("Cache-Control", "no-store")
        super().end_headers()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=8060)
    args = parser.parse_args()
    output = Path(__file__).resolve().parents[1] / "build" / "web"
    if not (output / "index.html").is_file():
        parser.error("No web build found. Run scripts/build_web.ps1 first.")
    handler = partial(WebBuildHandler, directory=str(output))
    server = ThreadingHTTPServer(("127.0.0.1", args.port), handler)
    print(f"NIGHT SCHOOL: http://127.0.0.1:{args.port}/", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
