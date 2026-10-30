import argparse
import webbrowser
from pathlib import Path

from .app import App
from .server import serve


def main():
    p = argparse.ArgumentParser(prog="lidtap", description="Zone taps on a MacBook lid from the built-in IMU.")
    p.add_argument("--port", type=int, default=8765)
    p.add_argument("--data", default=str(Path(__file__).resolve().parent.parent / "data"))
    p.add_argument("--open", action="store_true", help="open the GUI in the default browser")
    args = p.parse_args()

    app = App(args.data)
    app.start()
    httpd = serve(app, args.port)
    url = f"http://127.0.0.1:{args.port}/"
    print(f"lidtap running at {url}  (data in {args.data})", flush=True)
    if args.open:
        webbrowser.open(url)
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
