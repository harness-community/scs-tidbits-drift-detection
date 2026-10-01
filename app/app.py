from flask import Flask

app = Flask(__name__)


@app.route("/")
def index():
    return "scs-tidbit-drift-app: hello from a provenance-verified build!\n"


@app.route("/health")
def health():
    return {"status": "ok"}


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
