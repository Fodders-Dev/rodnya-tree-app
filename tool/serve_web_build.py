from __future__ import annotations

import argparse
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


class NoCacheStaticHandler(SimpleHTTPRequestHandler):
    def end_headers(self) -> None:
        self.send_header("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0")
        self.send_header("Pragma", "no-cache")
        self.send_header("Expires", "0")
        super().end_headers()


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Serve build/web with no-cache headers for local Flutter E2E checks."
    )
    parser.add_argument(
        "--directory",
        default="build/web",
        help="Directory to serve. Defaults to build/web.",
    )
    parser.add_argument(
        "--bind",
        default="127.0.0.1",
        help="Bind address. Defaults to 127.0.0.1.",
    )
    parser.add_argument(
        "--port",
        default=3000,
        type=int,
        help="Port to serve on. Defaults to 3000.",
    )
    args = parser.parse_args()

    directory = Path(args.directory).resolve()
    if not directory.exists():
        raise SystemExit(f"Directory does not exist: {directory}")

    handler = partial(NoCacheStaticHandler, directory=str(directory))
    server = ThreadingHTTPServer((args.bind, args.port), handler)
    print(f"[serve_web_build] serving {directory} at http://{args.bind}:{args.port}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
